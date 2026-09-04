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
use nsl_inet.stream_dhcp.all;
use nsl_inet.stream_host.all;

-- The turnkey host with DHCP enabled against a bench DHCP server, at
-- every supported width.  The server answers the DISCOVER and
-- REQUEST broadcasts with checksummed broadcast replies, then the
-- lease is exercised: the host answers a ping at the leased address,
-- and an application datagram is delivered and echoed, resolving the
-- peer through ARP on the way out.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 5);

  constant local_mac_c : mac48_t := from_hex("0221cafedeca");
  constant peer_mac_c : mac48_t := from_hex("06070809aabb");
  constant peer_ip_c : ipv4_t := to_ipv4(10, 0, 0, 2);
  constant server_ip_c : ipv4_t := to_ipv4(10, 0, 0, 9);
  constant leased_ip_c : ipv4_t := to_ipv4(10, 0, 0, 42);
  constant mask_c : ipv4_t := to_ipv4(255, 255, 255, 0);
  constant router_c : ipv4_t := to_ipv4(10, 0, 0, 254);
  constant dns_c : ipv4_t := to_ipv4(10, 0, 0, 53);
  constant ntp_c : ipv4_t := to_ipv4(10, 0, 0, 123);
  constant bcast_ip_c : ipv4_t := to_ipv4(255, 255, 255, 255);
  constant zero_ip_c : ipv4_t := to_ipv4(0, 0, 0, 0);
  constant l1_content_c : byte_string(0 to 4) := from_hex("b1b2b3b4b5");
  constant ports_c : integer_vector(0 to 0) := (0 => 1234);
  constant hostname_c : string := "nsl";

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

  -- UDP datagram with a valid checksum over the given pseudo-header
  -- addresses.
  function udp_pdu(src, dst: ipv4_t;
                   sport, dport: integer;
                   payload: byte_string) return byte_string
  is
    variable hdr: byte_string(0 to 7);
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    hdr(0 to 1) := to_be(to_unsigned(sport, 16));
    hdr(2 to 3) := to_be(to_unsigned(dport, 16));
    hdr(4 to 5) := to_be(to_unsigned(8 + payload'length, 16));
    hdr(6 to 7) := from_hex("0000");

    acc := checksum_update(acc, src & dst
                           & to_byte(0) & to_byte(ip_proto_udp)
                           & hdr(4 to 5));
    acc := checksum_update(acc, hdr & payload);
    if payload'length mod 2 = 1 then
      acc := checksum_update(acc, to_byte(0));
    end if;
    hdr(6 to 7) := checksum_spill(acc);
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

  function ip_pkt(src, dst: ipv4_t;
                  proto: integer; pdu: byte_string) return byte_string
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
    hdr(12 to 15) := src;
    hdr(16 to 19) := dst;

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

  -- Server-side BOOTP reply, padded to the minimum payload length.
  function dhcp_reply(msg_type: byte;
                      xid: byte_string;
                      yiaddr: ipv4_t) return byte_string
  is
    variable ret: byte_string(0 to dhcp_min_payload_length_c-1)
      := (others => x"00");
    variable o: integer;

    procedure opt4(code: byte; value: byte_string) is
    begin
      ret(o) := code;
      ret(o + 1) := to_byte(4);
      ret(o + 2 to o + 5) := value;
      o := o + 6;
    end procedure;
  begin
    ret(0) := dhcp_op_bootreply_c;
    ret(1) := to_byte(1);
    ret(2) := to_byte(6);
    ret(4 to 7) := xid;
    ret(16 to 19) := yiaddr;
    ret(28 to 33) := local_mac_c;
    ret(236 to 239) := dhcp_magic_cookie_c;

    o := 240;
    ret(o) := dhcp_option_message_type_c;
    ret(o + 1) := to_byte(1);
    ret(o + 2) := msg_type;
    o := o + 3;
    opt4(dhcp_option_server_id_c, server_ip_c);
    opt4(dhcp_option_netmask_c, mask_c);
    opt4(dhcp_option_router_c, router_c);
    opt4(dhcp_option_dns_c, dns_c);
    opt4(dhcp_option_ntp_servers_c, ntp_c);
    opt4(dhcp_option_lease_time_c, to_be(to_unsigned(600, 32)));
    ret(o) := dhcp_option_end_c;
    return ret;
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
    signal to_app_s : master_vector(0 to 0);
    signal to_app_ack_s : slave_vector(0 to 0);
    signal from_app_s : master_vector(0 to 0);
    signal from_app_ack_s : slave_vector(0 to 0);
    signal dhcp_address_s, dhcp_netmask_s : ipv4_t;
    signal dhcp_router_s, dhcp_dns_s, dhcp_ntp_s : ipv4_t;
    signal dhcp_valid_s : std_ulogic;

    function wire_frame(dest: mac48_t; ethertype: ethertype_t;
                        l3: byte_string) return byte_string
    is
      constant zeros_c: byte_string(1 to frame_off_c) := (others => x"00");
    begin
      return l1_padded_c
        & zeros_c
        & frame_pack(dest, peer_mac_c, ethertype, l3, 64);
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
  begin

    app: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable rejected_v: boolean;
    begin
      from_app_s(0) <= transfer_defaults(cfg_c);
      to_app_ack_s(0) <= accept(cfg_c, false);
      wait for 100 ns;

      clear(rx_v);
      loop
        receive(cfg_c, clock_s, to_app_s(0), to_app_ack_s(0), beat_v);
        for k in 0 to byte_count(cfg_c, beat_v)-1
        loop
          write(rx_v, beat_v.data(k));
        end loop;
        if is_last(cfg_c, beat_v) then
          rejected_v := is_rejected(cfg_c, beat_v);
          exit;
        end if;
      end loop;
      assert_equal("W" & to_string(width_c) & " datagram in",
                   rx_v.all, app_rx_pkt(9999, 16, 1), failure);
      assert not rejected_v
        report "Valid datagram should not be rejected"
        severity failure;
      deallocate(rx_v);

      packet_send(cfg_c, clock_s, from_app_ack_s(0), from_app_s(0),
                  packet => app_pkt(9999, 12, 2), user => "0");

      log_info("W" & to_string(width_c) & " host app OK");
      done_s(wl2 * 2 + 1) <= '1';
      wait;
    end process;

    peer: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable xid_v: byte_string(0 to 3);

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

      -- Option lookup over the frame's DHCP payload, options
      -- starting at frame offset 282.  Returns an empty slice when
      -- absent.
      impure function opt_get(code: byte; len: integer) return byte_string
      is
        variable o: integer := 282;
        variable empty_v: byte_string(0 to -1);
      begin
        while o < rx_v.all'length - (pre_size_c + frame_off_c)
        loop
          if fb(o) = dhcp_option_end_c then
            exit;
          elsif fb(o) = dhcp_option_pad_c then
            o := o + 1;
          elsif fb(o) = code then
            assert_equal("option " & to_string(to_integer(code)) & " length",
                         to_integer(fb(o+1)), len, failure);
            return fslice(o + 2, o + 1 + len);
          else
            o := o + 2 + to_integer(fb(o+1));
          end if;
        end loop;
        return empty_v;
      end function;

      procedure check_dhcp_out(constant what: string;
                               constant msg_type: byte)
      is
      begin
        rx_frame;
        assert_equal(what & " dest", fslice(0, 5), ethernet_broadcast_addr_c,
                     failure);
        assert_equal(what & " ethertype", fslice(12, 13), from_hex("0800"),
                     failure);
        assert_equal(what & " proto", fb(23), to_byte(ip_proto_udp), failure);
        assert_equal(what & " ip src", fslice(26, 29), zero_ip_c, failure);
        assert_equal(what & " ip dest", fslice(30, 33), bcast_ip_c, failure);
        assert checksum_is_valid(fslice(14, 33))
          report what & ": IP header checksum does not verify"
          severity failure;
        assert_equal(what & " sport",
                     to_integer(from_be(fslice(34, 35))),
                     dhcp_client_port_c, failure);
        assert_equal(what & " dport",
                     to_integer(from_be(fslice(36, 37))),
                     dhcp_server_port_c, failure);
        assert to_integer(from_be(fslice(38, 39)))
          >= 8 + dhcp_min_payload_length_c
          report what & ": short DHCP payload"
          severity failure;
        assert_equal(what & " op", fb(42), dhcp_op_bootrequest_c, failure);
        assert_equal(what & " flags", fslice(52, 53), from_hex("8000"),
                     failure);
        assert_equal(what & " ciaddr", fslice(54, 57), zero_ip_c, failure);
        assert_equal(what & " chaddr", fslice(70, 75), local_mac_c, failure);
        assert_equal(what & " cookie", fslice(278, 281), dhcp_magic_cookie_c,
                     failure);
        assert_equal(what & " message type",
                     opt_get(dhcp_option_message_type_c, 1),
                     (0 => msg_type), failure);
        assert_equal(what & " client id",
                     opt_get(dhcp_option_client_id_c, 7),
                     to_byte(1) & local_mac_c, failure);
        assert_equal(what & " hostname",
                     opt_get(dhcp_option_hostname_c, hostname_c'length),
                     to_byte_string(hostname_c), failure);
        xid_v := fslice(46, 49);
      end procedure;
    begin
      wire_out_s.s <= accept(cfg_c, false);
      wire_in_s.m <= transfer_defaults(cfg_c);
      wait for 100 ns;

      -- Acquisition
      check_dhcp_out("discover", dhcp_msg_discover_c);

      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(
                    ethernet_broadcast_addr_c, 16#0800#,
                    ip_pkt(server_ip_c, bcast_ip_c, ip_proto_udp,
                           udp_pdu(server_ip_c, bcast_ip_c,
                                   dhcp_server_port_c, dhcp_client_port_c,
                                   dhcp_reply(dhcp_msg_offer_c, xid_v,
                                              leased_ip_c)))),
                  user => "0");

      check_dhcp_out("request", dhcp_msg_request_c);
      assert_equal("request requested address",
                   opt_get(dhcp_option_requested_address_c, 4),
                   leased_ip_c, failure);
      assert_equal("request server id",
                   opt_get(dhcp_option_server_id_c, 4),
                   server_ip_c, failure);

      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(
                    ethernet_broadcast_addr_c, 16#0800#,
                    ip_pkt(server_ip_c, bcast_ip_c, ip_proto_udp,
                           udp_pdu(server_ip_c, bcast_ip_c,
                                   dhcp_server_port_c, dhcp_client_port_c,
                                   dhcp_reply(dhcp_msg_ack_c, xid_v,
                                              leased_ip_c)))),
                  user => "0");

      if dhcp_valid_s /= '1' then
        wait until dhcp_valid_s = '1' for 100 us;
      end if;
      assert dhcp_valid_s = '1'
        report "W" & to_string(width_c) & ": no lease acquired"
        severity failure;
      wait until falling_edge(clock_s);
      assert_equal("W" & to_string(width_c) & " leased address",
                   dhcp_address_s, leased_ip_c, failure);
      assert_equal("W" & to_string(width_c) & " leased netmask",
                   dhcp_netmask_s, mask_c, failure);
      assert_equal("W" & to_string(width_c) & " leased router",
                   dhcp_router_s, router_c, failure);
      assert_equal("W" & to_string(width_c) & " leased dns",
                   dhcp_dns_s, dns_c, failure);
      assert_equal("W" & to_string(width_c) & " leased ntp server",
                   dhcp_ntp_s, ntp_c, failure);

      -- Ping the leased address
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(
                    local_mac_c, 16#0800#,
                    ip_pkt(peer_ip_c, leased_ip_c, ip_proto_icmp,
                           icmp_pdu(8, payload_gen(3, 18)))),
                  user => "0");
      rx_frame;
      assert_equal("echo reply proto", fb(23), to_byte(ip_proto_icmp),
                   failure);
      assert_equal("echo reply ip src", fslice(26, 29), leased_ip_c, failure);
      assert_equal("echo reply ip dest", fslice(30, 33), peer_ip_c, failure);
      assert_equal("echo reply type", fb(34), to_byte(0), failure);

      -- Datagram to the application; the reply resolves the peer
      -- through ARP
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(
                    local_mac_c, 16#0800#,
                    ip_pkt(peer_ip_c, leased_ip_c, ip_proto_udp,
                           udp_pdu(peer_ip_c, leased_ip_c, 9999, 1234,
                                   payload_gen(1, 16)))),
                  user => "0");

      rx_frame;
      assert_equal("arp req dest", fslice(0, 5), ethernet_broadcast_addr_c,
                   failure);
      assert_equal("arp req ethertype", fslice(12, 13), from_hex("0806"),
                   failure);
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0806#,
                                       arp_payload(2, peer_mac_c, peer_ip_c,
                                                   local_mac_c, leased_ip_c)),
                  user => "0");

      rx_frame;
      assert_equal("reply dest", fslice(0, 5), peer_mac_c, failure);
      assert_equal("reply proto", fb(23), to_byte(ip_proto_udp), failure);
      assert_equal("reply ip src", fslice(26, 29), leased_ip_c, failure);
      assert_equal("reply sport",
                   to_integer(from_be(fslice(34, 35))), 1234, failure);
      assert_equal("reply dport",
                   to_integer(from_be(fslice(36, 37))), 9999, failure);
      assert_equal("reply payload", fslice(42, 41 + 12),
                   payload_gen(2, 12), failure);

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
        retry_count_c => 2,
        dhcp_c => true,
        clock_i_hz_c => 1000,
        hostname_c => hostname_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_hwaddr_i => local_mac_c,

        dhcp_address_o => dhcp_address_s,
        dhcp_netmask_o => dhcp_netmask_s,
        dhcp_router_o => dhcp_router_s,
        dhcp_dns_o => dhcp_dns_s,
        dhcp_ntp_server_o => dhcp_ntp_s,
        dhcp_valid_o => dhcp_valid_s,

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
