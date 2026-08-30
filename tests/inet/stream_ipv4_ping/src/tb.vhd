library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.mac.all;
use nsl_inet.ipv4.all;
use nsl_inet.checksum.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.stream_ethernet.all;
use nsl_inet.stream_ipv4.all;

-- Ping against the full AXI4-Stream stack: wire-level ICMP echo
-- request frames enter the mac receiver, traverse the ethernet and
-- IPv4 layers, get answered by the echo responder, and come back
-- through the IPv4, ethernet and mac transmitters as wire-level echo
-- replies, at every supported width and with a 5-byte layer-1 block
-- riding the whole loop.  Requests whose ICMP checksum or FCS is
-- corrupted yield replies cancelled on the wire through a corrupted
-- FCS.  Non-echo ICMP messages yield no reply.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

  constant local_mac_c : mac48_t := from_hex("0221cafedeca");
  constant peer_mac_c : mac48_t := from_hex("06070809aabb");
  constant local_ip_c : ipv4_t := to_ipv4(10, 0, 0, 1);
  constant peer_ip_c : ipv4_t := to_ipv4(10, 0, 0, 2);
  constant l1_content_c : byte_string(0 to 4) := from_hex("b1b2b3b4b5");

  function payload_gen(seq, len: integer) return byte_string
  is
    variable ret: byte_string(0 to len-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((seq * 11 + k * 3) mod 256);
    end loop;
    return ret;
  end function;

  -- ICMP message with the given type, valid checksum unless
  -- corrupted.
  function icmp_pdu(msg_type: integer;
                    payload: byte_string;
                    corrupt: boolean := false) return byte_string
  is
    variable ret: byte_string(0 to 3 + payload'length);
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    ret(0) := to_byte(msg_type);
    ret(1) := to_byte(0);
    ret(2 to 3) := from_hex("0000");
    ret(4 to ret'right) := payload;

    acc := checksum_update(acc, ret);
    if ret'length mod 2 = 1 then
      acc := checksum_update(acc, to_byte(0));
    end if;
    ret(2 to 3) := checksum_spill(acc);

    if corrupt then
      ret(2) := not ret(2);
    end if;
    return ret;
  end function;

  -- IPv4 packet from peer to the local station.
  function ip_pkt(pdu: byte_string) return byte_string
  is
    variable hdr: byte_string(0 to 19);
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    hdr(0) := to_byte(16#45#);
    hdr(1) := to_byte(0);
    hdr(2 to 3) := to_be(to_unsigned(20 + pdu'length, 16));
    hdr(4 to 5) := from_hex("1234");
    hdr(6 to 7) := from_hex("4000");
    hdr(8) := to_byte(63);
    hdr(9) := to_byte(ip_proto_icmp);
    hdr(10 to 11) := from_hex("0000");
    hdr(12 to 15) := peer_ip_c;
    hdr(16 to 19) := local_ip_c;

    acc := checksum_update(acc, hdr);
    hdr(10 to 11) := checksum_spill(acc);
    return hdr & pdu;
  end function;

begin

  w_gen: for wl2 in 0 to 2 generate
    constant width_c : natural := 2 ** wl2;
    constant cfg_c: config_t := stream_config(width_c);
    constant hdr_l1_c: integer_vector(0 to 0) := (0 => l1_content_c'length);
    constant hdr_l2_c: integer_vector(0 to 1)
      := (l1_content_c'length, l2_context_length_c);
    constant hdr_l3_c: integer_vector(0 to 2)
      := (l1_content_c'length, l2_context_length_c, ip_context_length_c);
    constant pre_size_c: natural := context_byte_count(cfg_c, hdr_l1_c);
    constant frame_off_c: natural := ethernet_frame_offset(cfg_c);

    signal wire_in_s, wire_out_s : bus_t;
    signal mac_to_eth_s, eth_to_mac_s : bus_t;
    signal eth_to_ip_s, ip_to_eth_s : bus_t;
    signal ip_to_icmp_s, icmp_to_ip_s : bus_t;

    -- Wire-level frame around an IP packet, with the layer-1 block
    -- and the frame front padding in place.
    function wire_frame(l3: byte_string) return byte_string
    is
      constant zeros_c: byte_string(1 to frame_off_c) := (others => x"00");
    begin
      return context_pad(cfg_c, l1_content_c)
        & zeros_c
        & frame_pack(local_mac_c, peer_mac_c, 16#0800#, l3, 64);
    end function;
  begin

    stim: process is
      procedure ping(constant l3: byte_string;
                     constant corrupt_fcs: boolean := false)
      is
        variable f_v: byte_string(0 to 255);
        variable flen_v: integer;
      begin
        -- Frame is header + payload padded to the minimum size + FCS
        flen_v := l3'length + 14 + 4;
        if flen_v < 64 then
          flen_v := 64;
        end if;
        flen_v := flen_v + pre_size_c + frame_off_c;

        f_v(0 to flen_v-1) := wire_frame(l3);
        if corrupt_fcs then
          f_v(flen_v-1) := not f_v(flen_v-1);
        end if;
        packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                    packet => f_v(0 to flen_v-1), user => "0");
      end procedure;
    begin
      wire_in_s.m <= transfer_defaults(cfg_c);
      wait for 100 ns;

      -- Exact minimum-size frame, no mac padding anywhere
      ping(ip_pkt(icmp_pdu(8, payload_gen(0, 22))));
      -- Odd payload, request padded by the sender, trimmed by the
      -- IPv4 layer, reply re-padded by the mac transmitter
      ping(ip_pkt(icmp_pdu(8, payload_gen(1, 5))));
      -- Corrupted ICMP checksum: reply cancelled on the wire
      ping(ip_pkt(icmp_pdu(8, payload_gen(2, 22), corrupt => true)));
      -- Non-echo messages: no reply at all
      ping(ip_pkt(icmp_pdu(0, payload_gen(3, 10))));
      ping(ip_pkt(icmp_pdu(3, payload_gen(4, 10))));
      -- Corrupted FCS: rejected by the mac receiver, reply cancelled
      ping(ip_pkt(icmp_pdu(8, payload_gen(5, 30))), corrupt_fcs => true);
      -- Stack still alive
      ping(ip_pkt(icmp_pdu(8, payload_gen(6, 40))));
      wait;
    end process;

    check: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;

      -- Receives one wire frame, checks the layer-1 block and front
      -- padding, and leaves the ethernet frame in frame_v.
      procedure rx_frame(variable frame_v: inout byte_stream)
      is
      begin
        clear(rx_v);
        loop
          receive(cfg_c, clock_s, wire_out_s.m, wire_out_s.s, beat_v);
          for k in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, beat_v.data(k));
          end loop;
          if is_last(cfg_c, beat_v) then
            exit;
          end if;
        end loop;

        assert_equal("W" & to_string(width_c) & " layer-1 block",
                     rx_v.all(0 to pre_size_c-1),
                     context_pad(cfg_c, l1_content_c), failure);

        clear(frame_v);
        for k in pre_size_c + frame_off_c to rx_v.all'right
        loop
          write(frame_v, rx_v.all(k));
        end loop;
      end procedure;

      procedure check_reply(constant seq, len: integer;
                            constant what: string)
      is
        variable frame_v: byte_stream;
        variable total_v, pdu_len_v: integer;
      begin
        rx_frame(frame_v);

        assert frame_is_fcs_valid(frame_v.all)
          report "W" & to_string(width_c) & " " & what & ": bad FCS"
          severity failure;
        assert_equal(what & " dest", frame_daddr_get(frame_v.all),
                     peer_mac_c, failure);
        assert_equal(what & " src", frame_saddr_get(frame_v.all),
                     local_mac_c, failure);
        assert_equal(what & " ethertype", frame_ethertype_get(frame_v.all),
                     16#0800#, failure);

        assert frame_v.all'length >= 14 + 20 + 4
          report what & ": reply frame too short"
          severity failure;

        assert_equal(what & " version", frame_v.all(14), to_byte(16#45#),
                     failure);
        total_v := to_integer(from_be(frame_v.all(16 to 17)));
        assert_equal(what & " total length", total_v, 20 + 4 + len,
                     failure);
          assert_equal(what & " fragment", frame_v.all(20 to 21),
                       from_hex("4000"), failure);
          assert_equal(what & " ttl", frame_v.all(22), to_byte(64), failure);
          assert_equal(what & " proto", frame_v.all(23),
                       to_byte(ip_proto_icmp), failure);
          assert_equal(what & " ip src", frame_v.all(26 to 29), local_ip_c,
                       failure);
          assert_equal(what & " ip dest", frame_v.all(30 to 33), peer_ip_c,
                       failure);
          assert checksum_is_valid(frame_v.all(14 to 33))
            report what & ": IP header checksum does not verify"
            severity failure;

        pdu_len_v := total_v - 20;
        assert_equal(what & " icmp type", frame_v.all(34), to_byte(0),
                     failure);
        assert checksum_is_valid(frame_v.all(34 to 34 + pdu_len_v - 1))
          report what & ": ICMP checksum does not verify"
          severity failure;
        assert_equal(what & " payload",
                     frame_v.all(38 to 34 + pdu_len_v - 1),
                     payload_gen(seq, len), failure);

        deallocate(frame_v);
      end procedure;

      procedure check_cancelled(constant what: string)
      is
        variable frame_v: byte_stream;
      begin
        rx_frame(frame_v);
        assert not frame_is_fcs_valid(frame_v.all)
          report "W" & to_string(width_c) & " " & what
          & ": cancelled reply should carry a bad FCS"
          severity failure;
        deallocate(frame_v);
      end procedure;
    begin
      wire_out_s.s <= accept(cfg_c, false);
      wait for 100 ns;

      check_reply(0, 22, "ping 0");
      check_reply(1, 5, "ping 1");
      check_cancelled("bad icmp checksum");
      check_cancelled("bad fcs");
      check_reply(6, 40, "ping 6");

      log_info("W" & to_string(width_c) & " ping OK");
      done_s(wl2) <= '1';
      wait;
    end process;

    mac_rx: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l1_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        in_i => wire_in_s.m,
        in_o => wire_in_s.s,
        out_o => mac_to_eth_s.m,
        out_i => mac_to_eth_s.s
        );

    mac_tx: nsl_inet.stream_mac.stream_mac_transmitter
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l1_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        in_i => eth_to_mac_s.m,
        in_o => eth_to_mac_s.s,
        out_o => wire_out_s.m,
        out_i => wire_out_s.s
        );

    eth: nsl_inet.stream_ethernet.stream_ethernet_layer
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l1_c,
        ethertype_c => (0 => 16#0800#)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_mac_c,

        to_l3_o(0) => eth_to_ip_s.m,
        to_l3_i(0) => eth_to_ip_s.s,
        from_l3_i(0) => ip_to_eth_s.m,
        from_l3_o(0) => ip_to_eth_s.s,

        to_l1_o => eth_to_mac_s.m,
        to_l1_i => eth_to_mac_s.s,
        from_l1_i => mac_to_eth_s.m,
        from_l1_o => mac_to_eth_s.s
        );

    ip: nsl_inet.stream_ipv4.stream_ipv4_layer
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l2_c,
        ip_proto_c => (0 => ip_proto_icmp)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_ip_c,

        to_l4_o(0) => ip_to_icmp_s.m,
        to_l4_i(0) => ip_to_icmp_s.s,
        from_l4_i(0) => icmp_to_ip_s.m,
        from_l4_o(0) => icmp_to_ip_s.s,

        to_l3_o => ip_to_eth_s.m,
        to_l3_i => ip_to_eth_s.s,
        from_l3_i => eth_to_ip_s.m,
        from_l3_o => eth_to_ip_s.s
        );

    icmp: nsl_inet.stream_ipv4.stream_ipv4_icmp_echo
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l3_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => ip_to_icmp_s.m,
        in_o => ip_to_icmp_s.s,

        out_o => icmp_to_ip_s.m,
        out_i => icmp_to_ip_s.s
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
        bus_i => wire_in_s
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
