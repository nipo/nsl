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
use nsl_inet.stream_udp.all;
use nsl_inet.stream_host.all;

-- The turnkey host against a bench peer, at every supported width.
-- Application 0 sends a datagram to a fresh peer, triggering ARP
-- resolution before the datagram leaves.  The peer then sends a
-- datagram to application 1, which answers by echoing the context
-- blocks; the reply leaves with no ARP traffic (the cache learned
-- from the first exchange).  The peer pings the host, then sends a
-- datagram with a corrupted UDP checksum, delivered rejected.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 5);

  constant local_mac_c : mac48_t := from_hex("0221cafedeca");
  constant peer_mac_c : mac48_t := from_hex("06070809aabb");
  constant local_ip_c : ipv4_t := to_ipv4(10, 0, 0, 1);
  constant peer_ip_c : ipv4_t := to_ipv4(10, 0, 0, 2);
  constant l1_content_c : byte_string(0 to 4) := from_hex("b1b2b3b4b5");
  constant ports_c : integer_vector(0 to 1) := (1234, 5353);

  function payload_gen(seq, len: integer) return byte_string
  is
    variable ret: byte_string(0 to len-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((seq * 17 + k * 3) mod 256);
    end loop;
    return ret;
  end function;

  -- UDP datagram from the peer to the local station, checksummed.
  function udp_pdu(sport, dport: integer;
                   payload: byte_string;
                   corrupt: boolean := false) return byte_string
  is
    variable hdr: byte_string(0 to 7);
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    hdr(0 to 1) := to_be(to_unsigned(sport, 16));
    hdr(2 to 3) := to_be(to_unsigned(dport, 16));
    hdr(4 to 5) := to_be(to_unsigned(8 + payload'length, 16));
    hdr(6 to 7) := from_hex("0000");

    acc := checksum_update(acc, peer_ip_c & local_ip_c
                           & to_byte(0) & to_byte(ip_proto_udp)
                           & hdr(4 to 5));
    acc := checksum_update(acc, hdr & payload);
    if payload'length mod 2 = 1 then
      acc := checksum_update(acc, to_byte(0));
    end if;
    hdr(6 to 7) := checksum_spill(acc);

    if corrupt then
      hdr(6) := not hdr(6);
    end if;
    return hdr & payload;
  end function;

  function icmp_pdu(msg_type: integer;
                    payload: byte_string) return byte_string
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
    return ret;
  end function;

  -- IPv4 packet from the peer to the local station.
  function ip_pkt(proto: integer; pdu: byte_string) return byte_string
  is
    variable hdr: byte_string(0 to 19);
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    hdr(0) := to_byte(16#45#);
    hdr(1) := to_byte(0);
    hdr(2 to 3) := to_be(to_unsigned(20 + pdu'length, 16));
    hdr(4 to 5) := from_hex("2222");
    hdr(6 to 7) := from_hex("4000");
    hdr(8) := to_byte(63);
    hdr(9) := to_byte(proto);
    hdr(10 to 11) := from_hex("0000");
    hdr(12 to 15) := peer_ip_c;
    hdr(16 to 19) := local_ip_c;

    acc := checksum_update(acc, hdr);
    hdr(10 to 11) := checksum_spill(acc);
    return hdr & pdu;
  end function;

  function arp_payload(oper: integer;
                       sha: mac48_t; spa: ipv4_t;
                       tha: mac48_t; tpa: ipv4_t) return byte_string
  is
  begin
    return from_hex("000108000604")
      & to_be(to_unsigned(oper, 16))
      & sha & spa & tha & tpa;
  end function;

begin

  w_gen: for wl2 in 0 to 2 generate
    constant width_c : natural := 2 ** wl2;
    constant cfg_c: config_t := stream_config(width_c);
    constant hdr_l1_c: integer_vector(0 to 0) := (0 => l1_content_c'length);
    constant pre_size_c: natural := context_byte_count(cfg_c, hdr_l1_c);
    constant frame_off_c: natural := ethernet_frame_offset(cfg_c);
    constant l1_padded_c: byte_string(0 to pre_size_c-1)
      := context_pad(cfg_c, l1_content_c);

    signal wire_in_s, wire_out_s : bus_t;
    signal to_app_s : master_vector(0 to 1);
    signal to_app_ack_s : slave_vector(0 to 1);
    signal from_app_s : master_vector(0 to 1);
    signal from_app_ack_s : slave_vector(0 to 1);

    function wire_frame(dest: mac48_t; ethertype: ethertype_t;
                        l3: byte_string) return byte_string
    is
      constant zeros_c: byte_string(1 to frame_off_c) := (others => x"00");
    begin
      return l1_padded_c
        & zeros_c
        & frame_pack(dest, peer_mac_c, ethertype, l3, 64);
    end function;

    -- Application-side transmit packet toward a peer port.
    function app_pkt(dport, payload_len, seq: integer) return byte_string
    is
      variable l3ctx: ip_context_t;
      variable l4ctx: udp_context_t;
    begin
      l3ctx.peer := peer_ip_c;
      l3ctx.casting := IP_CAST_UNICAST;
      l3ctx.length := 8 + payload_len;
      l4ctx.peer_port := dport;
      return context_pad(cfg_c, to_bytes(l3ctx))
        & context_pad(cfg_c, to_bytes(l4ctx))
        & payload_gen(seq, payload_len);
    end function;

    -- Application-side receive image of a datagram from the peer.
    function app_rx_pkt(sport, payload_len, seq: integer) return byte_string
    is
      variable l2ctx: l2_context_t;
      variable l3ctx: ip_context_t;
      variable l4ctx: udp_context_t;
    begin
      l2ctx.peer := peer_mac_c;
      l2ctx.casting := L2_CAST_UNICAST;
      l3ctx.peer := peer_ip_c;
      l3ctx.casting := IP_CAST_UNICAST;
      l3ctx.length := 8 + payload_len;
      l4ctx.peer_port := sport;
      return l1_padded_c
        & context_pad(cfg_c, to_bytes(l2ctx))
        & context_pad(cfg_c, to_bytes(l3ctx))
        & context_pad(cfg_c, to_bytes(l4ctx))
        & payload_gen(seq, payload_len);
    end function;
  begin

    app0: process is
    begin
      from_app_s(0) <= transfer_defaults(cfg_c);
      to_app_ack_s(0) <= accept(cfg_c, false);
      wait for 100 ns;

      packet_send(cfg_c, clock_s, from_app_ack_s(0), from_app_s(0),
                  packet => app_pkt(7777, 32, 0), user => "0");
      wait;
    end process;

    app1: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable rejected_v: boolean;

      procedure rx_pkt is
      begin
        clear(rx_v);
        loop
          receive(cfg_c, clock_s, to_app_s(1), to_app_ack_s(1), beat_v);
          for k in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, beat_v.data(k));
          end loop;
          if is_last(cfg_c, beat_v) then
            rejected_v := is_rejected(cfg_c, beat_v);
            exit;
          end if;
        end loop;
      end procedure;
    begin
      from_app_s(1) <= transfer_defaults(cfg_c);
      to_app_ack_s(1) <= accept(cfg_c, false);
      wait for 100 ns;

      rx_pkt;
      assert_equal("W" & to_string(width_c) & " datagram in",
                   rx_v.all, app_rx_pkt(9999, 15, 1), failure);
      assert not rejected_v
        report "Valid datagram should not be rejected"
        severity failure;
      deallocate(rx_v);

      packet_send(cfg_c, clock_s, from_app_ack_s(1), from_app_s(1),
                  packet => app_pkt(9999, 11, 2), user => "0");

      rx_pkt;
      assert_equal("W" & to_string(width_c) & " corrupted datagram in",
                   rx_v.all, app_rx_pkt(9999, 10, 4), failure);
      assert rejected_v
        report "Corrupted datagram should be rejected"
        severity failure;
      deallocate(rx_v);

      log_info("W" & to_string(width_c) & " host app OK");
      done_s(wl2 * 2 + 1) <= '1';
      wait;
    end process;

    peer: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;

      procedure rx_frame is
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

        assert frame_is_fcs_valid(rx_v.all(pre_size_c + frame_off_c
                                           to rx_v.all'right))
          report "W" & to_string(width_c) & ": frame with bad FCS"
          severity failure;
      end procedure;

      impure function fb(k: integer) return byte
      is
      begin
        return rx_v.all(pre_size_c + frame_off_c + k);
      end function;

      impure function fslice(f, l: integer) return byte_string
      is
      begin
        return rx_v.all(pre_size_c + frame_off_c + f
                        to pre_size_c + frame_off_c + l);
      end function;

      procedure check_udp_out(constant sport, dport, len, seq: integer;
                              constant what: string)
      is
      begin
        rx_frame;
        assert_equal(what & " dest", fslice(0, 5), peer_mac_c, failure);
        assert_equal(what & " ethertype", fslice(12, 13), from_hex("0800"),
                     failure);
        assert_equal(what & " proto", fb(23), to_byte(ip_proto_udp), failure);
        assert_equal(what & " ip dest", fslice(30, 33), peer_ip_c, failure);
        assert checksum_is_valid(fslice(14, 33))
          report what & ": IP header checksum does not verify"
          severity failure;
        assert_equal(what & " sport",
                     to_integer(from_be(fslice(34, 35))), sport, failure);
        assert_equal(what & " dport",
                     to_integer(from_be(fslice(36, 37))), dport, failure);
        assert_equal(what & " udp length",
                     to_integer(from_be(fslice(38, 39))), 8 + len, failure);
        assert_equal(what & " udp checksum", fslice(40, 41),
                     from_hex("0000"), failure);
        assert_equal(what & " payload", fslice(42, 41 + len),
                     payload_gen(seq, len), failure);
      end procedure;
    begin
      wire_out_s.s <= accept(cfg_c, false);
      wire_in_s.m <= transfer_defaults(cfg_c);
      wait for 100 ns;

      -- Resolution of application 0's datagram
      rx_frame;
      assert_equal("arp req dest", fslice(0, 5), ethernet_broadcast_addr_c,
                   failure);
      assert_equal("arp req ethertype", fslice(12, 13), from_hex("0806"),
                   failure);
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0806#,
                                       arp_payload(2, peer_mac_c, peer_ip_c,
                                                   local_mac_c, local_ip_c)),
                  user => "0");

      check_udp_out(1234, 7777, 32, 0, "datagram out");

      -- Datagram to application 1, then its reply, with no ARP
      -- traffic in between
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0800#,
                                       ip_pkt(ip_proto_udp,
                                              udp_pdu(9999, 5353,
                                                      payload_gen(1, 15)))),
                  user => "0");

      check_udp_out(5353, 9999, 11, 2, "reply out");

      -- Ping the host
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0800#,
                                       ip_pkt(ip_proto_icmp,
                                              icmp_pdu(8, payload_gen(3, 18)))),
                  user => "0");
      rx_frame;
      assert_equal("echo reply ethertype", fslice(12, 13), from_hex("0800"),
                   failure);
      assert_equal("echo reply proto", fb(23), to_byte(ip_proto_icmp),
                   failure);
      assert_equal("echo reply type", fb(34), to_byte(0), failure);
      assert checksum_is_valid(fslice(34, 34 + 4 + 18 - 1))
        report "Echo reply ICMP checksum does not verify"
        severity failure;
      assert_equal("echo reply payload", fslice(38, 38 + 18 - 1),
                   payload_gen(3, 18), failure);

      -- Corrupted UDP checksum, delivered rejected
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0800#,
                                       ip_pkt(ip_proto_udp,
                                              udp_pdu(9999, 5353,
                                                      payload_gen(4, 10),
                                                      corrupt => true))),
                  user => "0");

      log_info("W" & to_string(width_c) & " host peer OK");
      done_s(wl2 * 2) <= '1';
      wait;
    end process;

    dut: nsl_inet.stream_host.stream_ipv4_host
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l1_c,
        udp_port_c => ports_c,
        cache_count_l2_c => 2,
        timeout_c => 4096,
        retry_count_c => 2
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_hwaddr_i => local_mac_c,
        local_address_i => local_ip_c,

        l1_header_i => l1_padded_c,

        l1_rx_i => wire_in_s.m,
        l1_rx_o => wire_in_s.s,
        l1_tx_o => wire_out_s.m,
        l1_tx_i => wire_out_s.s,

        to_app_o => to_app_s,
        to_app_i => to_app_ack_s,
        from_app_i => from_app_s,
        from_app_o => from_app_ack_s
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
