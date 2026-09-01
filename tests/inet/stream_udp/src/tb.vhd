library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.checksum.all;
use nsl_inet.ipv4.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.stream_udp.all;

-- Stream UDP layer test.
--
-- One layer instance per stream width, each with two application
-- pipes.  Every instance forwards three blocks, the last one being
-- the IPv4 context the layer reads for the pseudo-header and the
-- datagram length; the other two are filled with a pattern that must
-- reach the other side untouched, block padding included.
--
-- The receive phase feeds datagrams to the IPv4 side: valid ones on
-- both ports, a datagram without checksum, one whose checksum does
-- not verify, one whose length field disagrees with the IPv4
-- context, one for a port nobody listens to, one arriving rejected,
-- odd and empty payloads, then a burst of small datagrams at line
-- rate with a backpressure monitor armed on the IPv4-side input.
--
-- The transmit phase feeds the application pipes, including a
-- datagram whose blocks are the ones extracted from the first
-- received datagram, so that the crafted destination port is checked
-- against the source port of that datagram.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 3;
  constant width_list_c : integer_vector(0 to instance_count_c-1)
    := (1, 2, 4);
  -- A layer-1 block, the layer-2 context, the IPv4 context
  constant lengths_c : integer_vector(0 to 2) := (5, 7, ip_context_length_c);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c * 3 - 1);

  constant local_c : ipv4_t := to_ipv4(10, 0, 0, 1);
  constant peer_a_c : ipv4_t := to_ipv4(10, 0, 0, 2);
  constant peer_b_c : ipv4_t := to_ipv4(10, 0, 0, 3);

  constant udp_port_list_c : integer_vector(0 to 1) := (1234, 5353);
  constant unknown_port_c : natural := 9999;

  -- Indices of the receive datagrams exercising one rule each
  constant rx_zero_checksum_c : natural := 2;
  constant rx_corrupt_c : natural := 3;
  constant rx_length_mismatch_c : natural := 4;
  constant rx_unknown_port_c : natural := 5;
  constant rx_rejected_c : natural := 6;
  constant rx_odd_c : natural := 7;
  constant rx_empty_c : natural := 8;
  constant rx_rejected_odd_c : natural := 9;

  constant directed_count_c : natural := 11;
  constant linerate_count_c : natural := 24;
  constant rx_count_c : natural := directed_count_c + linerate_count_c;
  -- Largest datagram, UDP header and payload
  constant max_datagram_c : natural := 8 + 20;

  constant tx_count_c : natural := 5;
  -- Index of the transmit datagram whose blocks are echoed back from
  -- the receive path
  constant tx_echo_c : natural := 2;

  function rx_pipe(idx: integer) return natural
  is
  begin
    case idx is
      when 1 => return 1;
      when rx_corrupt_c => return 1;
      when rx_odd_c => return 1;
      when rx_rejected_odd_c => return 1;
      when others =>
        if idx >= directed_count_c and idx mod 2 = 1 then
          return 1;
        else
          return 0;
        end if;
    end case;
  end function;

  function rx_destination_port(idx: integer) return natural
  is
  begin
    if idx = rx_unknown_port_c then
      return unknown_port_c;
    end if;
    return udp_port_list_c(rx_pipe(idx));
  end function;

  function rx_source_port(idx: integer) return natural
  is
  begin
    return 40000 + idx;
  end function;

  function rx_peer(idx: integer) return ipv4_t
  is
  begin
    if idx mod 2 = 0 then
      return peer_a_c;
    else
      return peer_b_c;
    end if;
  end function;

  function rx_payload_length(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 16;
      when 1 => return 12;
      when rx_zero_checksum_c => return 8;
      when rx_corrupt_c => return 10;
      when rx_length_mismatch_c => return 6;
      when rx_unknown_port_c => return 6;
      when rx_rejected_c => return 4;
      when rx_odd_c => return 13;
      when rx_empty_c => return 0;
      when rx_rejected_odd_c => return 1;
      when 10 => return 20;
      when others => return (idx * 3) mod 9;
    end case;
  end function;

  -- Datagram length the IPv4 context declares, which is also the
  -- count of bytes the IPv4 layer hands over.
  function rx_ip_length(idx: integer) return natural
  is
  begin
    return 8 + rx_payload_length(idx);
  end function;

  -- Length field of the UDP header.  One datagram disagrees with the
  -- IPv4 context.
  function rx_udp_length(idx: integer) return natural
  is
  begin
    if idx = rx_length_mismatch_c then
      return rx_ip_length(idx) + 1;
    end if;
    return rx_ip_length(idx);
  end function;

  -- A zero checksum field means the sender did not compute one.
  function rx_no_checksum(idx: integer) return boolean
  is
  begin
    return idx = rx_zero_checksum_c
      or (idx >= directed_count_c and idx mod 5 = 0);
  end function;

  function rx_corrupt(idx: integer) return boolean
  is
  begin
    return idx = rx_corrupt_c;
  end function;

  -- Datagrams arriving rejected must have a payload: an empty packet
  -- carries no beat past the header the router rewrites.
  function rx_arrives_rejected(idx: integer) return boolean
  is
  begin
    return idx = rx_rejected_c or idx = rx_rejected_odd_c;
  end function;

  function rx_accepted(idx: integer) return boolean
  is
  begin
    return idx /= rx_length_mismatch_c and idx /= rx_unknown_port_c;
  end function;

  function rx_delivered_rejected(idx: integer) return boolean
  is
  begin
    return rx_arrives_rejected(idx) or rx_corrupt(idx);
  end function;

  function rx_payload(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to rx_payload_length(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 13 + k * 7 + 5) mod 256);
    end loop;
    return ret;
  end function;

  -- Pseudo-header of RFC 768, built here from the datagram fields
  -- independently of what the layer reads from the stream.
  function rx_pseudo_header(idx: integer) return byte_string
  is
  begin
    return rx_peer(idx) & local_c & to_byte(0) & to_byte(ip_proto_udp)
      & to_be(to_unsigned(rx_udp_length(idx), 16));
  end function;

  function rx_udp_header(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to 7) := (others => x"00");
    variable chk: checksum_acc_t := checksum_acc_init_c;
  begin
    ret(0 to 1) := to_be(to_unsigned(rx_source_port(idx), 16));
    ret(2 to 3) := to_be(to_unsigned(rx_destination_port(idx), 16));
    ret(4 to 5) := to_be(to_unsigned(rx_udp_length(idx), 16));

    if not rx_no_checksum(idx) then
      chk := checksum_update(chk,
                             rx_pseudo_header(idx) & ret & rx_payload(idx));
      ret(6 to 7) := checksum_spill(chk,
                                    is_misaligned =>
                                      rx_payload_length(idx) mod 2 = 1);

      if rx_corrupt(idx) then
        ret(6) := ret(6) xor x"55";
        assert ret(6 to 7) /= byte_string'(x"00", x"00")
          report "Corrupted checksum field must stay non-zero"
          severity failure;
      end if;
    end if;

    return ret;
  end function;

  function tx_pipe(idx: integer) return natural
  is
  begin
    case idx is
      when 1 => return 1;
      when 3 => return 1;
      when others => return 0;
    end case;
  end function;

  -- Destination port of the crafted header.  The echoed datagram
  -- must reach the source port of the datagram its context came from.
  function tx_peer_port(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 40000;
      when 1 => return 5353;
      when tx_echo_c => return rx_source_port(0);
      when 3 => return 4000;
      when others => return 1234;
    end case;
  end function;

  function tx_peer(idx: integer) return ipv4_t
  is
  begin
    if idx = tx_echo_c then
      return rx_peer(0);
    elsif idx mod 2 = 0 then
      return peer_a_c;
    else
      return peer_b_c;
    end if;
  end function;

  -- The echoed datagram carries the length of the IPv4 context it
  -- got, so its payload has to match.
  function tx_payload_length(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 16;
      when 1 => return 0;
      when tx_echo_c => return rx_payload_length(0);
      when 3 => return 5;
      when others => return 8;
    end case;
  end function;

  function tx_payload(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to tx_payload_length(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 31 + k * 3 + 17) mod 256);
    end loop;
    return ret;
  end function;

begin

  context_encoding: process is
    variable ctx: udp_context_t;
    variable b: byte_string(0 to udp_context_length_c-1);
  begin
    ctx.peer_port := 16#1234#;
    b := to_bytes(ctx);
    assert_equal("context high byte", b(0), to_byte(16#12#), failure);
    assert_equal("context low byte", b(1), to_byte(16#34#), failure);
    assert_equal("context peer port", from_bytes(b).peer_port,
                 ctx.peer_port, failure);

    ctx.peer_port := 0;
    b := to_bytes(ctx);
    assert_equal("context peer port", from_bytes(b).peer_port, 0, failure);
    wait;
  end process;

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant cfg_c : config_t := stream_config(width_c);
    -- Transported size of the blocks the layer forwards verbatim
    constant pre_c : natural := context_byte_count(cfg_c, lengths_c);
    constant ip_ctx_off_c : natural
      := pre_c - context_byte_count(cfg_c, (0 => ip_context_length_c));
    constant ctx_c : natural
      := context_byte_count(cfg_c, (0 => udp_context_length_c));
    constant ipg_beats_c : natural := 20 / width_c;
    constant name_c : string
      := to_string(cfg_c) & " blocks " & to_string(pre_c);

    -- Contents of the forwarded blocks, padding bytes included: the
    -- layer has no business knowing where the padding starts.
    function pre_pattern return byte_string
    is
      variable ret: byte_string(0 to pre_c-1);
    begin
      for k in ret'range
      loop
        ret(k) := to_byte((k * 37 + 16#a5#) mod 256);
      end loop;
      return ret;
    end function;

    constant pre_pat_c : byte_string(0 to pre_c-1) := pre_pattern;

    signal l4_in_s, l4_out_s : bus_t;
    signal app_rx_s, app_tx_s : bus_vector(0 to 1);

    signal monitor_en_s : std_ulogic;
    signal echo_valid_s : std_ulogic;
    signal echo_blocks_s : byte_string(0 to pre_c + ctx_c - 1);

    -- Forwarded blocks of a received datagram, the IPv4 context
    -- overwriting the pattern in the last one.
    function rx_blocks(idx: integer) return byte_string
    is
      variable ret: byte_string(0 to pre_c-1) := pre_pat_c;
    begin
      ret(ip_ctx_off_c to ip_ctx_off_c + ip_context_length_c-1)
        := to_bytes(ip_context_t'(peer => rx_peer(idx),
                                  casting => IP_CAST_UNICAST,
                                  length => rx_ip_length(idx)));
      return ret;
    end function;

    function rx_wire(idx: integer) return byte_string
    is
    begin
      return rx_blocks(idx) & rx_udp_header(idx) & rx_payload(idx);
    end function;

    function rx_expected(idx: integer) return byte_string
    is
      constant ctx_v: udp_context_t := (peer_port => rx_source_port(idx));
    begin
      return rx_blocks(idx) & context_pad(cfg_c, to_bytes(ctx_v))
        & rx_payload(idx);
    end function;

    function tx_blocks(idx: integer) return byte_string
    is
      variable ret: byte_string(0 to pre_c-1) := pre_pat_c;
    begin
      if idx = tx_echo_c then
        return rx_blocks(0);
      end if;

      ret(ip_ctx_off_c to ip_ctx_off_c + ip_context_length_c-1)
        := to_bytes(ip_context_t'(peer => tx_peer(idx),
                                  casting => IP_CAST_UNICAST,
                                  length => 8 + tx_payload_length(idx)));
      return ret;
    end function;

    function tx_packet(idx: integer) return byte_string
    is
      constant ctx_v: udp_context_t := (peer_port => tx_peer_port(idx));
    begin
      return tx_blocks(idx) & context_pad(cfg_c, to_bytes(ctx_v))
        & tx_payload(idx);
    end function;

    procedure pipe_check(constant pipe: natural;
                         signal stream_i: in master_t;
                         signal stream_o: out slave_t;
                         variable first_blocks: out byte_string)
    is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable data_v: byte_string(0 to cfg_c.data_width-1);
      variable got_first_v: boolean := false;
    begin
      stream_o <= accept(cfg_c, false);
      wait for 40 ns;

      for idx in 0 to rx_count_c-1
      loop
        next when not rx_accepted(idx);
        next when rx_pipe(idx) /= pipe;

        clear(rx_v);
        loop
          receive(cfg_c, clock_s, stream_i, stream_o, beat_v);

          assert is_packed(cfg_c, beat_v)
            report name_c & " pipe " & to_string(pipe)
            & " datagram " & to_string(idx) & ": sparse keep pattern"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          if is_last(cfg_c, beat_v) then
            assert is_rejected(cfg_c, beat_v) = rx_delivered_rejected(idx)
              report name_c & " pipe " & to_string(pipe)
              & " datagram " & to_string(idx)
              & ": unexpected reject flag state"
              severity failure;
            exit;
          end if;
        end loop;

        assert_equal(name_c & " pipe " & to_string(pipe)
                     & " datagram " & to_string(idx),
                     rx_v.all, rx_expected(idx), failure);

        if not got_first_v then
          first_blocks := rx_v.all(rx_v.all'left
                                   to rx_v.all'left + pre_c + ctx_c - 1);
          got_first_v := true;
        end if;

        deallocate(rx_v);
      end loop;

      assert got_first_v
        report name_c & " pipe " & to_string(pipe) & ": no datagram received"
        severity failure;
    end procedure;

  begin

    l4_stim: process is
      variable user_v: std_ulogic_vector(0 to 0);
    begin
      l4_in_s.m <= transfer_defaults(cfg_c);
      monitor_en_s <= '1';
      wait for 200 ns;
      wait until falling_edge(clock_s);

      for idx in 0 to rx_count_c-1
      loop
        user_v := "0";
        if rx_arrives_rejected(idx) then
          user_v := "1";
        end if;

        packet_send(cfg_c, clock_s, l4_in_s.s, l4_in_s.m,
                    packet => rx_wire(idx), user => user_v);

        for i in 1 to ipg_beats_c
        loop
          wait until falling_edge(clock_s);
        end loop;
      end loop;

      monitor_en_s <= '0';
      wait;
    end process;

    rx0_check: process is
      variable blocks_v: byte_string(0 to pre_c + ctx_c - 1);
    begin
      echo_valid_s <= '0';
      echo_blocks_s <= (others => x"00");

      pipe_check(0, app_rx_s(0).m, app_rx_s(0).s, blocks_v);

      echo_blocks_s <= blocks_v;
      echo_valid_s <= '1';

      log_info(name_c & " receive pipe 0 OK");
      done_s(inst * 3 + 0) <= '1';
      wait;
    end process;

    rx1_check: process is
      variable blocks_v: byte_string(0 to pre_c + ctx_c - 1);
    begin
      pipe_check(1, app_rx_s(1).m, app_rx_s(1).s, blocks_v);

      log_info(name_c & " receive pipe 1 OK");
      done_s(inst * 3 + 1) <= '1';
      wait;
    end process;

    tx_stim: process is
      procedure tx_send(constant pipe: natural;
                        constant packet: byte_string)
      is
      begin
        if pipe = 0 then
          packet_send(cfg_c, clock_s, app_tx_s(0).s, app_tx_s(0).m,
                      packet => packet, user => "0");
        else
          packet_send(cfg_c, clock_s, app_tx_s(1).s, app_tx_s(1).m,
                      packet => packet, user => "0");
        end if;
      end procedure;
    begin
      app_tx_s(0).m <= transfer_defaults(cfg_c);
      app_tx_s(1).m <= transfer_defaults(cfg_c);

      wait until echo_valid_s = '1';
      wait until falling_edge(clock_s);

      -- Datagrams from distinct pipes back to back, the funnel has to
      -- serialize them in offering order.
      for idx in 0 to tx_count_c-1
      loop
        if idx = tx_echo_c then
          tx_send(tx_pipe(idx), echo_blocks_s & tx_payload(idx));
        else
          tx_send(tx_pipe(idx), tx_packet(idx));
        end if;
      end loop;
      wait;
    end process;

    tx_check: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable data_v: byte_string(0 to cfg_c.data_width-1);

      procedure header_check(constant idx: natural;
                             constant packet: byte_string)
      is
        alias xp: byte_string(0 to packet'length-1) is packet;
        constant header_c: byte_string(0 to 7) := xp(pre_c to pre_c + 7);
        constant what_c: string
          := name_c & " transmit datagram " & to_string(idx);
      begin
        assert_equal(what_c & " forwarded blocks",
                     xp(0 to pre_c-1), tx_blocks(idx), failure);
        assert_equal(what_c & " source port",
                     to_integer(from_be(header_c(0 to 1))),
                     udp_port_list_c(tx_pipe(idx)), failure);
        assert_equal(what_c & " destination port",
                     to_integer(from_be(header_c(2 to 3))),
                     tx_peer_port(idx), failure);
        assert_equal(what_c & " length",
                     to_integer(from_be(header_c(4 to 5))),
                     8 + tx_payload_length(idx), failure);
        assert_equal(what_c & " checksum field",
                     to_integer(from_be(header_c(6 to 7))), 0, failure);
        assert_equal(what_c & " payload",
                     xp(pre_c + 8 to xp'right), tx_payload(idx), failure);
      end procedure;
    begin
      l4_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for idx in 0 to tx_count_c-1
      loop
        clear(rx_v);
        loop
          receive(cfg_c, clock_s, l4_out_s.m, l4_out_s.s, beat_v);

          assert is_packed(cfg_c, beat_v)
            report name_c & " IPv4 output: sparse keep pattern"
            severity failure;

          assert not is_rejected(cfg_c, beat_v)
            report name_c & " IPv4 output: unexpected reject flag"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          exit when is_last(cfg_c, beat_v);
        end loop;

        header_check(idx, rx_v.all);

        deallocate(rx_v);
      end loop;

      log_info(name_c & " transmit OK");
      done_s(inst * 3 + 2) <= '1';
      wait;
    end process;

    monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "UDP_RX_W" & to_string(width_c),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        enable_i => monitor_en_s,
        bus_i => l4_in_s
        );

    dut: nsl_inet.stream_udp.stream_udp_layer
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c,
        udp_port_c => udp_port_list_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_c,

        to_app_o(0) => app_rx_s(0).m,
        to_app_o(1) => app_rx_s(1).m,
        to_app_i(0) => app_rx_s(0).s,
        to_app_i(1) => app_rx_s(1).s,

        from_app_i(0) => app_tx_s(0).m,
        from_app_i(1) => app_tx_s(1).m,
        from_app_o(0) => app_tx_s(0).s,
        from_app_o(1) => app_tx_s(1).s,

        to_l4_o => l4_out_s.m,
        to_l4_i => l4_out_s.s,
        from_l4_i => l4_in_s.m,
        from_l4_o => l4_in_s.s
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
