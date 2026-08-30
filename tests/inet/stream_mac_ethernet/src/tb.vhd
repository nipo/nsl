library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.stream_ethernet.all;

-- Full-chain loopback of the AXI4-Stream ethernet stack: L3 packets
-- go through the ethernet transmitter, the mac transmitter, a wire
-- loop, the mac receiver and the ethernet receiver, at 1, 2 and
-- 4 byte widths, with a 5-byte forwarded block ahead of everything.
-- Frames are addressed to the local station, or broadcast, so the
-- receive side accepts them.  Checks cover verbatim block
-- forwarding, casting reporting, mac padding visibility, partial
-- last beats, funnel arbitration, and late cancellation: a packet
-- cancelled at L3 reaches the wire with a corrupted FCS and comes
-- back out rejected.  Backpressure monitors hold the
-- never-originate-slowdown contract on both receive-side inputs.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 5);

  constant local_c : mac48_t := from_hex("0221cafedeca");
  constant etypes_c : ethertype_vector(0 to 1) := (16#0800#, 16#0806#);
  constant pre_content_c : byte_string(0 to 4) := from_hex("a1a2a3a4a5");

  -- Payload and mac padding land on the L3 receive side unmodified.
  -- The mac transmitter pads frames to the ethernet minimum and to
  -- the next beat boundary, so a payload comes back zero-padded to
  -- whatever the frame grew to, minus the ethernet header.
  function l3_padded_length(cfg: config_t; length: natural) return natural
  is
    constant offset_c: natural := ethernet_frame_offset(cfg);
    variable ret: natural := ethernet_header_length_c + length;
  begin
    if ret < 60 then
      ret := 60;
    end if;
    while (ret + offset_c) mod cfg.data_width /= 0
    loop
      ret := ret + 1;
    end loop;
    return ret - ethernet_header_length_c;
  end function;

  type pkt_t is
  record
    len: integer;
    rejected: boolean;
    broadcast: boolean;
  end record;

  type pkt_vector is array(natural range <>) of pkt_t;

  constant p0_c: pkt_vector(0 to 3) := ((100, false, false),
                                        (10, false, false),
                                        (20, true, false),
                                        (47, false, false));
  constant p1_c: pkt_vector(0 to 1) := ((49, false, false),
                                        (46, false, true));

  function pkt_of(pipe, seq: integer) return pkt_t
  is
  begin
    if pipe = 0 then
      return p0_c(seq);
    else
      return p1_c(seq);
    end if;
  end function;

  function pkt_count(pipe: integer) return integer
  is
  begin
    if pipe = 0 then
      return p0_c'length;
    else
      return p1_c'length;
    end if;
  end function;

  function payload_gen(pipe, seq, len: integer) return byte_string
  is
    variable ret: byte_string(0 to len-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((pipe * 32 + seq * 7 + k * 5) mod 256);
    end loop;
    return ret;
  end function;

  function if_user(rejected: boolean) return std_ulogic_vector
  is
  begin
    if rejected then
      return "1";
    else
      return "0";
    end if;
  end function;

  function sent_gen(cfg: config_t; pipe, seq: integer) return byte_string
  is
    constant pkt_c: pkt_t := pkt_of(pipe, seq);
    variable ctx: l2_context_t;
  begin
    if pkt_c.broadcast then
      ctx.peer := (others => x"ff");
    else
      ctx.peer := local_c;
    end if;
    ctx.casting := L2_CAST_UNICAST;

    return context_pad(cfg, pre_content_c)
      & context_pad(cfg, to_bytes(ctx))
      & payload_gen(pipe, seq, pkt_c.len);
  end function;

  -- L3-side view of a frame once looped through the stack: forwarded
  -- block, context reporting the sender and the casting, payload,
  -- then mac padding when the payload is short.
  function expected_gen(cfg: config_t; pipe, seq: integer) return byte_string
  is
    constant pkt_c: pkt_t := pkt_of(pipe, seq);
    constant padded_c: natural := l3_padded_length(cfg, pkt_c.len);
    variable ctx: l2_context_t;
  begin
    ctx.peer := local_c;
    if pkt_c.broadcast then
      ctx.casting := L2_CAST_BROADCAST;
    else
      ctx.casting := L2_CAST_UNICAST;
    end if;

    return context_pad(cfg, pre_content_c)
      & context_pad(cfg, to_bytes(ctx))
      & payload_gen(pipe, seq, pkt_c.len)
      & byte_string'(1 to padded_c - pkt_c.len => x"00");
  end function;

begin

  w_gen: for wl2 in 0 to 2 generate
    constant width_c : natural := 2 ** wl2;
    constant cfg_c: config_t := stream_config(width_c);
    constant hdr_c: integer_vector(0 to 0) := (0 => pre_content_c'length);

    signal to_l3_s : master_vector(0 to 1);
    signal to_l3_ack_s : slave_vector(0 to 1);
    signal from_l3_s : master_vector(0 to 1);
    signal from_l3_ack_s : slave_vector(0 to 1);
    signal eth_to_mac_s, wire_s, mac_to_eth_s : bus_t;
  begin

    pipe_gen: for p in 0 to 1 generate
    begin
      stim: process is
      begin
        from_l3_s(p) <= transfer_defaults(cfg_c);
        wait for 100 ns;

        for seq in 0 to pkt_count(p)-1
        loop
          packet_send(cfg_c, clock_s, from_l3_ack_s(p), from_l3_s(p),
                      packet => sent_gen(cfg_c, p, seq),
                      user => if_user(pkt_of(p, seq).rejected));
        end loop;
        wait;
      end process;

      check: process is
        variable beat_v: master_t;
        variable rx_v: byte_stream;
        variable rejected_v: boolean;
      begin
        to_l3_ack_s(p) <= accept(cfg_c, false);
        wait for 100 ns;

        for seq in 0 to pkt_count(p)-1
        loop
          clear(rx_v);
          loop
            receive(cfg_c, clock_s, to_l3_s(p), to_l3_ack_s(p), beat_v);
            for k in 0 to byte_count(cfg_c, beat_v)-1
            loop
              write(rx_v, beat_v.data(k));
            end loop;
            if is_last(cfg_c, beat_v) then
              rejected_v := is_rejected(cfg_c, beat_v);
              exit;
            end if;
          end loop;

          assert_equal("W" & to_string(width_c)
                       & " pipe " & to_string(p)
                       & " packet " & to_string(seq),
                       rx_v.all, expected_gen(cfg_c, p, seq), failure);

          assert rejected_v = pkt_of(p, seq).rejected
            report "W" & to_string(width_c)
            & " pipe " & to_string(p)
            & " packet " & to_string(seq)
            & ": unexpected reject flag state"
            severity failure;
          deallocate(rx_v);
        end loop;

        log_info("W" & to_string(width_c)
                 & " pipe " & to_string(p) & " chain OK");
        done_s(wl2 * 2 + p) <= '1';
        wait;
      end process;
    end generate;

    eth: nsl_inet.stream_ethernet.stream_ethernet_layer
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c,
        ethertype_c => etypes_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_c,

        to_l3_o => to_l3_s,
        to_l3_i => to_l3_ack_s,
        from_l3_i => from_l3_s,
        from_l3_o => from_l3_ack_s,

        to_l1_o => eth_to_mac_s.m,
        to_l1_i => eth_to_mac_s.s,
        from_l1_i => mac_to_eth_s.m,
        from_l1_o => mac_to_eth_s.s
        );

    mac_tx: nsl_inet.stream_mac.stream_mac_transmitter
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => eth_to_mac_s.m,
        in_o => eth_to_mac_s.s,

        out_o => wire_s.m,
        out_i => wire_s.s
        );

    mac_rx: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => wire_s.m,
        in_o => wire_s.s,

        out_o => mac_to_eth_s.m,
        out_i => mac_to_eth_s.s
        );

    wire_monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "WIRE_W" & to_string(width_c),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => wire_s
        );

    l2_monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "L2_W" & to_string(width_c),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => mac_to_eth_s
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
