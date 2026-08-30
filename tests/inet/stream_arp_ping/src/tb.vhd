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
use nsl_inet.stream_resolver.all;
use nsl_inet.stream_arp.all;

-- Outbound ping with live address resolution: an application hands
-- the resolver entry point [IPv4 context][ICMP echo request] without
-- knowing anything below; the entry queries the ARP resolver, whose
-- cache miss puts a broadcast ARP request on the wire.  The bench
-- plays the peer: it answers the ARP request, receives the ICMP echo
-- request, and sends the echo reply, which climbs back to the
-- application through the receive path.  A second ping to the same
-- peer produces no ARP traffic (cache hit).  The peer also sends an
-- ARP request for the local station and checks the reply.
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
      ret(k) := to_byte((seq * 13 + k * 7) mod 256);
    end loop;
    return ret;
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
  function ip_pkt(pdu: byte_string) return byte_string
  is
    variable hdr: byte_string(0 to 19);
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    hdr(0) := to_byte(16#45#);
    hdr(1) := to_byte(0);
    hdr(2 to 3) := to_be(to_unsigned(20 + pdu'length, 16));
    hdr(4 to 5) := from_hex("4321");
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
    constant hdr_l2_c: integer_vector(0 to 1)
      := (l1_content_c'length, l2_context_length_c);
    constant pre_size_c: natural := context_byte_count(cfg_c, hdr_l1_c);
    constant frame_off_c: natural := ethernet_frame_offset(cfg_c);
    constant l1_padded_c: byte_string(0 to pre_size_c-1)
      := context_pad(cfg_c, l1_content_c);

    signal app_in_s, app_out_s : bus_t;
    signal wire_in_s, wire_out_s : bus_t;
    signal mac_to_eth_s, eth_to_mac_s : bus_t;
    signal entry_to_ip_s : bus_t;
    signal eth_to_ip_s, ip_to_eth_s : bus_t;
    signal eth_to_arp_s, arp_to_eth_s : bus_t;
    signal query_s, response_s : bus_t;

    function wire_frame(dest: mac48_t; ethertype: ethertype_t;
                        l3: byte_string) return byte_string
    is
      constant zeros_c: byte_string(1 to frame_off_c) := (others => x"00");
    begin
      return l1_padded_c
        & zeros_c
        & frame_pack(dest, peer_mac_c, ethertype, l3, 64);
    end function;
  begin

    app_stim: process is
      procedure app_send(constant seq, len: integer)
      is
        variable ctx: ip_context_t;
      begin
        ctx.peer := peer_ip_c;
        ctx.casting := IP_CAST_UNICAST;
        ctx.length := 4 + len;
        packet_send(cfg_c, clock_s, app_in_s.s, app_in_s.m,
                    packet => context_pad(cfg_c, to_bytes(ctx))
                    & icmp_pdu(8, payload_gen(seq, len)),
                    user => "0");
      end procedure;
    begin
      app_in_s.m <= transfer_defaults(cfg_c);
      wait for 100 ns;

      app_send(0, 20);
      app_send(1, 9);
      wait;
    end process;

    app_check: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;

      procedure check_reply(constant seq, len: integer;
                            constant what: string)
      is
        variable l2ctx: l2_context_t;
        variable l3ctx: ip_context_t;
      begin
        l2ctx.peer := peer_mac_c;
        l2ctx.casting := L2_CAST_UNICAST;
        l3ctx.peer := peer_ip_c;
        l3ctx.casting := IP_CAST_UNICAST;
        l3ctx.length := 4 + len;

        clear(rx_v);
        loop
          receive(cfg_c, clock_s, app_out_s.m, app_out_s.s, beat_v);
          for k in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, beat_v.data(k));
          end loop;
          if is_last(cfg_c, beat_v) then
            assert not is_rejected(cfg_c, beat_v)
              report what & ": reply should not be rejected"
              severity failure;
            exit;
          end if;
        end loop;

        assert_equal("W" & to_string(width_c) & " " & what,
                     rx_v.all,
                     l1_padded_c
                     & context_pad(cfg_c, to_bytes(l2ctx))
                     & context_pad(cfg_c, to_bytes(l3ctx))
                     & icmp_pdu(0, payload_gen(seq, len)),
                     failure);
        deallocate(rx_v);
      end procedure;
    begin
      app_out_s.s <= accept(cfg_c, false);
      wait for 100 ns;

      check_reply(0, 20, "reply 0");
      check_reply(1, 9, "reply 1");

      log_info("W" & to_string(width_c) & " arp ping OK");
      done_s(wl2) <= '1';
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

        assert_equal("W" & to_string(width_c) & " layer-1 block",
                     rx_v.all(0 to pre_size_c-1), l1_padded_c, failure);
        assert frame_is_fcs_valid(rx_v.all(pre_size_c + frame_off_c
                                           to rx_v.all'right))
          report "W" & to_string(width_c) & ": frame with bad FCS"
          severity failure;
      end procedure;

      -- Ethernet frame byte at index k, DA being byte 0
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

      procedure check_icmp_request(constant seq, len: integer;
                                   constant what: string)
      is
      begin
        rx_frame;
        assert_equal(what & " dest", fslice(0, 5), peer_mac_c, failure);
        assert_equal(what & " src", fslice(6, 11), local_mac_c, failure);
        assert_equal(what & " ethertype", fslice(12, 13), from_hex("0800"),
                     failure);
        assert_equal(what & " total length",
                     to_integer(from_be(fslice(16, 17))), 24 + len, failure);
        assert_equal(what & " proto", fb(23), to_byte(ip_proto_icmp), failure);
        assert_equal(what & " ip src", fslice(26, 29), local_ip_c, failure);
        assert_equal(what & " ip dest", fslice(30, 33), peer_ip_c, failure);
        assert checksum_is_valid(fslice(14, 33))
          report what & ": IP header checksum does not verify"
          severity failure;
        assert_equal(what & " icmp", fslice(34, 37 + len),
                     icmp_pdu(8, payload_gen(seq, len)), failure);
      end procedure;
    begin
      wire_out_s.s <= accept(cfg_c, false);
      wire_in_s.m <= transfer_defaults(cfg_c);
      wait for 100 ns;

      -- Resolution of the first ping: broadcast ARP request
      rx_frame;
      assert_equal("arp req dest", fslice(0, 5), ethernet_broadcast_addr_c,
                   failure);
      assert_equal("arp req src", fslice(6, 11), local_mac_c, failure);
      assert_equal("arp req ethertype", fslice(12, 13), from_hex("0806"),
                   failure);
      assert_equal("arp req payload", fslice(14, 41),
                   arp_payload(1, local_mac_c, local_ip_c,
                               from_hex("000000000000"), peer_ip_c),
                   failure);

      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0806#,
                                       arp_payload(2, peer_mac_c, peer_ip_c,
                                                   local_mac_c, local_ip_c)),
                  user => "0");

      -- Both pings must come out with no ARP traffic in between
      check_icmp_request(0, 20, "icmp req 0");
      check_icmp_request(1, 9, "icmp req 1");

      -- Peer request for the local station
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(ethernet_broadcast_addr_c, 16#0806#,
                                       arp_payload(1, peer_mac_c, peer_ip_c,
                                                   from_hex("000000000000"),
                                                   local_ip_c)),
                  user => "0");

      rx_frame;
      assert_equal("arp reply dest", fslice(0, 5), peer_mac_c, failure);
      assert_equal("arp reply ethertype", fslice(12, 13), from_hex("0806"),
                   failure);
      assert_equal("arp reply payload", fslice(14, 41),
                   arp_payload(2, local_mac_c, local_ip_c,
                               peer_mac_c, peer_ip_c),
                   failure);

      -- Echo replies for both pings
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0800#,
                                       ip_pkt(icmp_pdu(0, payload_gen(0, 20)))),
                  user => "0");
      packet_send(cfg_c, clock_s, wire_in_s.s, wire_in_s.m,
                  packet => wire_frame(local_mac_c, 16#0800#,
                                       ip_pkt(icmp_pdu(0, payload_gen(1, 9)))),
                  user => "0");
      wait;
    end process;

    entry: nsl_inet.stream_resolver.stream_resolver_entry
      generic map(
        config_c => cfg_c,
        query_length_c => ip_context_length_c,
        buffer_depth_l2_c => 8
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => app_in_s.m,
        in_o => app_in_s.s,

        query_o => query_s.m,
        query_i => query_s.s,
        response_i => response_s.m,
        response_o => response_s.s,

        out_o => entry_to_ip_s.m,
        out_i => entry_to_ip_s.s
        );

    arp: nsl_inet.stream_arp.stream_arp_resolver
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l1_c,
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

        from_l2_i => eth_to_arp_s.m,
        from_l2_o => eth_to_arp_s.s,
        to_l2_o => arp_to_eth_s.m,
        to_l2_i => arp_to_eth_s.s,

        query_i => query_s.m,
        query_o => query_s.s,

        response_o => response_s.m,
        response_i => response_s.s
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

        to_l4_o(0) => app_out_s.m,
        to_l4_i(0) => app_out_s.s,
        from_l4_i(0) => entry_to_ip_s.m,
        from_l4_o(0) => entry_to_ip_s.s,

        to_l3_o => ip_to_eth_s.m,
        to_l3_i => ip_to_eth_s.s,
        from_l3_i => eth_to_ip_s.m,
        from_l3_o => eth_to_ip_s.s
        );

    eth: nsl_inet.stream_ethernet.stream_ethernet_layer
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_l1_c,
        ethertype_c => (16#0800#, 16#0806#)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_mac_c,

        to_l3_o(0) => eth_to_ip_s.m,
        to_l3_o(1) => eth_to_arp_s.m,
        to_l3_i(0) => eth_to_ip_s.s,
        to_l3_i(1) => eth_to_arp_s.s,
        from_l3_i(0) => ip_to_eth_s.m,
        from_l3_i(1) => arp_to_eth_s.m,
        from_l3_o(0) => ip_to_eth_s.s,
        from_l3_o(1) => arp_to_eth_s.s,

        to_l1_o => eth_to_mac_s.m,
        to_l1_i => eth_to_mac_s.s,
        from_l1_i => mac_to_eth_s.m,
        from_l1_o => mac_to_eth_s.s
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
