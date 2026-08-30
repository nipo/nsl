library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.stream_resolver.all;
use nsl_inet.ipv4.all;
use nsl_inet.mac.all;

-- Address resolution service test.
--
-- One service instance per stream width: two application pipes, each
-- entering the stack through its own resolver entry, an arbiter
-- sharing a single static IPv4 resolver between the two entries.  The
-- resolver is configured with a two-entry address table and one
-- forwarded block of 5 bytes, filled with a pattern that must reach
-- the head of every response, its padding included.
--
-- The two pipes run their packet lists concurrently, so responses only
-- reach their expected entry if the arbiter tracks query order.  Each
-- list mixes packets that resolve, packets that must be dropped -- an
-- unknown peer, a remainder overflowing the entry buffer -- and
-- packets that must go through right after a drop.  The output of a
-- pipe is checked byte for byte, and is required to stay idle once its
-- last packet has been delivered.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 3;
  constant width_list_c : integer_vector(0 to instance_count_c-1) := (1, 2, 4);

  constant pipe_count_c : natural := 2;
  -- Entry 1 holds 16 beats, small enough for a packet list to overflow
  -- it on purpose.
  constant depth_l2_c : integer_vector(0 to pipe_count_c-1) := (6, 4);

  constant l1_length_c : natural := 5;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c * pipe_count_c - 1);

  constant addr_c : ipv4_vector(0 to 1)
    := (from_hex("c0a8010a"), from_hex("c0a8010b"));
  constant hwaddr_c : mac48_vector(0 to 1)
    := (from_hex("0200000a0a0a"), from_hex("0200000b0b0b"));
  constant unknown_c : ipv4_t := from_hex("c0a80163");
  constant broadcast_c : ipv4_t := from_hex("ffffffff");

  constant pkt_count_c : natural := 7;

  function pkt_peer(pipe, idx: natural) return ipv4_t
  is
  begin
    if pipe = 0 then
      case idx is
        when 1 => return broadcast_c;
        when 2 => return unknown_c;
        when 3 => return addr_c(1);
        when 5 => return addr_c(1);
        when others => return addr_c(0);
      end case;
    else
      case idx is
        when 1 => return addr_c(0);
        when 2 => return addr_c(0);
        when 3 => return unknown_c;
        when others => return addr_c(1);
      end case;
    end if;
  end function;

  function pkt_casting(pipe, idx: natural) return ip_casting_t
  is
  begin
    if pipe = 0 and idx = 1 then
      return IP_CAST_BROADCAST;
    else
      return IP_CAST_UNICAST;
    end if;
  end function;

  -- Payload length in bytes.  Payloads start on a beat boundary, so
  -- the remainder of a packet is the payload rounded up to a whole
  -- count of beats.
  function pkt_payload_length(pipe, idx, width: natural) return natural
  is
  begin
    if pipe = 0 then
      case idx is
        when 0 => return 20;
        when 1 => return 12;
        when 2 => return 16;
        when 3 => return 8;
        when 4 => return 24;
        when 5 => return 4;
        when others => return 32;
      end case;
    else
      case idx is
        when 0 => return 12;
        -- Twenty beats whatever the width, four more than the buffer
        -- of entry 1 holds
        when 1 => return 20 * width;
        when 2 => return 9;
        when 3 => return 5;
        when 4 => return 13;
        when 5 => return 16;
        -- Packet made of the query block alone: the response is the
        -- whole emitted packet, its last beat included
        when others => return 0;
      end case;
    end if;
  end function;

  -- Packets expected to reach the output of their pipe.  Packet 2 of
  -- pipe 0 and packet 3 of pipe 1 name a peer outside the address
  -- table, packet 1 of pipe 1 overflows the entry buffer.
  function pkt_pass(pipe, idx: natural) return boolean
  is
  begin
    if pipe = 0 then
      return idx /= 2;
    else
      return idx /= 1 and idx /= 3;
    end if;
  end function;

  function pkt_rejected(pipe, idx: natural) return boolean
  is
  begin
    return pipe = 0 and idx = 4;
  end function;

  function pkt_hwaddr(pipe, idx: natural) return mac48_t
  is
    constant peer_c: ipv4_t := pkt_peer(pipe, idx);
  begin
    if pkt_casting(pipe, idx) = IP_CAST_BROADCAST then
      return ethernet_broadcast_addr_c;
    end if;

    for i in addr_c'range
    loop
      if addr_c(i) = peer_c then
        return hwaddr_c(i);
      end if;
    end loop;

    return (others => x"00");
  end function;

  function pkt_l2_casting(pipe, idx: natural) return l2_casting_t
  is
  begin
    if pkt_casting(pipe, idx) = IP_CAST_BROADCAST then
      return L2_CAST_BROADCAST;
    else
      return L2_CAST_UNICAST;
    end if;
  end function;

begin

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant cfg_c : config_t := stream_config(width_c);
    constant l1_bytes_c : natural
      := context_byte_count(cfg_c, (0 => l1_length_c));

    function l1_pattern return byte_string
    is
      variable ret: byte_string(0 to l1_bytes_c-1);
    begin
      for k in ret'range
      loop
        ret(k) := to_byte((k * 37 + 16#a5#) mod 256);
      end loop;
      return ret;
    end function;

    constant l1_pat_c : byte_string(0 to l1_bytes_c-1) := l1_pattern;

    function pkt_payload(pipe, idx: natural) return byte_string
    is
      variable ret: byte_string(0 to pkt_payload_length(pipe, idx, width_c)-1);
    begin
      for k in ret'range
      loop
        ret(k) := to_byte((pipe * 97 + idx * 13 + k * 7 + 5) mod 256);
      end loop;
      return ret;
    end function;

    function pkt_ip_block(pipe, idx: natural) return byte_string
    is
    begin
      return context_pad(cfg_c,
                         to_bytes(ip_context_t'(
                           peer => pkt_peer(pipe, idx),
                           casting => pkt_casting(pipe, idx),
                           length => pkt_payload_length(pipe, idx, width_c))));
    end function;

    function pkt_in(pipe, idx: natural) return byte_string
    is
    begin
      return pkt_ip_block(pipe, idx) & pkt_payload(pipe, idx);
    end function;

    function pkt_out(pipe, idx: natural) return byte_string
    is
    begin
      return l1_pat_c
        & context_pad(cfg_c,
                      to_bytes(l2_context_t'(peer => pkt_hwaddr(pipe, idx),
                                             casting => pkt_l2_casting(pipe, idx))))
        & pkt_ip_block(pipe, idx)
        & pkt_payload(pipe, idx);
    end function;

    procedure pkt_send(signal stream_o: out master_t;
                       signal stream_i: in slave_t;
                       constant packet: byte_string;
                       constant rejected: boolean)
    is
      alias data_c: byte_string(0 to packet'length-1) is packet;
      constant beats_c: natural := (packet'length + width_c - 1) / width_c;
      variable chunk_v: byte_string(0 to width_c-1);
      variable keep_v: std_ulogic_vector(0 to width_c-1);
      variable user_v: std_ulogic_vector(0 to 0);
      variable first_v, count_v: natural;
    begin
      for b in 0 to beats_c-1
      loop
        first_v := b * width_c;
        count_v := width_c;
        if first_v + count_v > data_c'length then
          count_v := data_c'length - first_v;
        end if;

        chunk_v := (others => x"00");
        keep_v := (others => '0');
        for k in 0 to count_v-1
        loop
          chunk_v(k) := data_c(first_v + k);
          keep_v(k) := '1';
        end loop;

        user_v := "0";
        if b = beats_c-1 and rejected then
          user_v := "1";
        end if;

        stream_o <= transfer(cfg_c,
                             bytes => chunk_v,
                             keep => keep_v,
                             user => user_v,
                             valid => true,
                             last => b = beats_c-1);
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(cfg_c, stream_i);
        end loop;
        wait until falling_edge(clock_s);
      end loop;

      stream_o <= transfer_defaults(cfg_c);
    end procedure;

    procedure pkt_check(constant what: string;
                        signal stream_i: in master_t;
                        signal stream_o: out slave_t;
                        constant expected: byte_string;
                        constant rejected: boolean)
    is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable data_v: byte_string(0 to width_c-1);
    begin
      clear(rx_v);

      loop
        receive(cfg_c, clock_s, stream_i, stream_o, beat_v);

        assert is_packed(cfg_c, beat_v)
          report what & ": sparse keep pattern"
          severity failure;

        data_v := bytes(cfg_c, beat_v);
        for i in 0 to byte_count(cfg_c, beat_v)-1
        loop
          write(rx_v, data_v(i));
        end loop;

        if is_last(cfg_c, beat_v) then
          assert is_rejected(cfg_c, beat_v) = rejected
            report what & ": unexpected reject flag state"
            severity failure;
          exit;
        end if;
      end loop;

      assert_equal(what, rx_v.all, expected, failure);
      deallocate(rx_v);
    end procedure;

    procedure pkt_expect_idle(constant what: string;
                              signal stream_i: in master_t;
                              signal stream_o: out slave_t;
                              constant cycles: natural)
    is
    begin
      stream_o <= accept(cfg_c, true);
      for i in 1 to cycles
      loop
        wait until rising_edge(clock_s);
        assert not is_valid(cfg_c, stream_i)
          report what & ": beat after the last expected packet"
          severity failure;
        wait until falling_edge(clock_s);
      end loop;
      stream_o <= accept(cfg_c, false);
    end procedure;

    signal app_s, out_s, query_s, response_s : bus_vector(0 to pipe_count_c-1);
    signal resolver_query_s, resolver_response_s : bus_t;

  begin

    pipe_gen: for pipe in 0 to pipe_count_c-1 generate
      constant label_c : string
        := to_string(cfg_c) & " pipe " & to_string(pipe);
    begin

      stim: process is
      begin
        app_s(pipe).m <= transfer_defaults(cfg_c);
        wait for 200 ns;
        wait until falling_edge(clock_s);

        for idx in 0 to pkt_count_c-1
        loop
          pkt_send(app_s(pipe).m, app_s(pipe).s,
                   pkt_in(pipe, idx), pkt_rejected(pipe, idx));
        end loop;

        wait;
      end process;

      check: process is
      begin
        out_s(pipe).s <= accept(cfg_c, false);
        wait for 40 ns;

        for idx in 0 to pkt_count_c-1
        loop
          next when not pkt_pass(pipe, idx);

          pkt_check(label_c & " packet " & to_string(idx),
                    out_s(pipe).m, out_s(pipe).s,
                    pkt_out(pipe, idx), pkt_rejected(pipe, idx));
        end loop;

        pkt_expect_idle(label_c, out_s(pipe).m, out_s(pipe).s, 400);

        log_info(label_c & " OK");
        done_s(inst * pipe_count_c + pipe) <= '1';
        wait;
      end process;

      entry_inst: nsl_inet.stream_resolver.stream_resolver_entry
        generic map(
          config_c => cfg_c,
          query_length_c => ip_context_length_c,
          buffer_depth_l2_c => depth_l2_c(pipe)
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          in_i => app_s(pipe).m,
          in_o => app_s(pipe).s,

          query_o => query_s(pipe).m,
          query_i => query_s(pipe).s,
          response_i => response_s(pipe).m,
          response_o => response_s(pipe).s,

          out_o => out_s(pipe).m,
          out_i => out_s(pipe).s
          );
    end generate;

    arbiter: nsl_inet.stream_resolver.stream_resolver_arbiter
      generic map(
        config_c => cfg_c,
        source_count_c => pipe_count_c,
        pending_count_l2_c => 2
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        query_i(0) => query_s(0).m,
        query_i(1) => query_s(1).m,
        query_o(0) => query_s(0).s,
        query_o(1) => query_s(1).s,

        response_o(0) => response_s(0).m,
        response_o(1) => response_s(1).m,
        response_i(0) => response_s(0).s,
        response_i(1) => response_s(1).s,

        resolver_query_o => resolver_query_s.m,
        resolver_query_i => resolver_query_s.s,
        resolver_response_i => resolver_response_s.m,
        resolver_response_o => resolver_response_s.s
        );

    resolver: nsl_inet.stream_resolver.stream_resolver_static_ipv4
      generic map(
        config_c => cfg_c,
        header_length_c => integer_vector'(0 => l1_length_c),
        address_c => addr_c,
        hwaddr_c => hwaddr_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        l1_header_i => l1_pat_c,

        query_i => resolver_query_s.m,
        query_o => resolver_query_s.s,

        response_o => resolver_response_s.m,
        response_i => resolver_response_s.s
        );
  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
