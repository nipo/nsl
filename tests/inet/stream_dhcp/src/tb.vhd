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
use nsl_inet.stream.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.stream_udp.all;
use nsl_inet.stream_dhcp.all;

-- A DHCP client against a bench server.  The server walks the client
-- through discovery, selection, binding, two renewals and a final
-- NAK, checking the message layout and the lease outputs at each
-- step.  A second client, configured without a host name, only has
-- its first discovery inspected.
entity tb is
end tb;

architecture arch of tb is

  constant cfg_c : config_t := stream_config(1);
  constant hdr_c : integer_vector(0 to 3) := (5, 7, 7, 2);
  constant pre_size_c : natural := context_byte_count(cfg_c, hdr_c);
  constant prefix_c : byte_string(0 to pre_size_c-1) := (others => x"5a");

  constant ctx_size_c : natural
    := ip_context_length_c + udp_context_length_c;
  constant payload_length_c : natural := dhcp_min_payload_length_c;
  constant tx_length_c : natural := ctx_size_c + payload_length_c;

  constant cookie_off_c : natural := dhcp_header_length_c;
  constant options_off_c : natural := cookie_off_c + dhcp_magic_cookie_c'length;

  constant hostname_c : string := "nsl";

  -- Protocol second, as the ticker divider and as bench time
  constant client_hz_c : natural := 400;
  constant tick_c : time := 4 us;

  constant client_mac_c : mac48_t := from_hex("0221cafedeca");
  constant client_ip_c : ipv4_t := to_ipv4(192, 168, 1, 50);
  constant server_ip_c : ipv4_t := to_ipv4(192, 168, 1, 1);
  constant netmask_c : ipv4_t := to_ipv4(255, 255, 255, 0);
  constant router_c : ipv4_t := to_ipv4(192, 168, 1, 254);
  constant dns_c : ipv4_t := to_ipv4(192, 168, 1, 53);
  constant decoy_ip_c : ipv4_t := to_ipv4(10, 9, 9, 9);
  constant decoy_netmask_c : ipv4_t := to_ipv4(255, 0, 0, 0);
  constant any_ip_c : ipv4_t := to_ipv4(0, 0, 0, 0);
  constant broadcast_ip_c : ipv4_t := to_ipv4(255, 255, 255, 255);

  constant chaddr_pad_c : byte_string(0 to 9) := (others => x"00");
  constant option_end_c : byte_string(0 to 0) := (0 => dhcp_option_end_c);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal rx_s, tx_s : bus_t;
  signal address_s, netmask_s, router_s, dns_s : ipv4_t;
  signal valid_s : std_ulogic;

  signal rx2_s, tx2_s : bus_t;
  signal address2_s, netmask2_s, router2_s, dns2_s : ipv4_t;
  signal valid2_s : std_ulogic;

  function opt(code: byte; data: byte_string) return byte_string
  is
    constant head_c: byte_string(0 to 1)
      := (0 => code, 1 => to_byte(data'length));
  begin
    return head_c & data;
  end function;

  function opt(code: byte; data: byte) return byte_string
  is
    constant one_c: byte_string(0 to 0) := (0 => data);
  begin
    return opt(code, one_c);
  end function;

  function opt32(code: byte; value: natural) return byte_string
  is
  begin
    return opt(code, to_be(to_unsigned(value, 32)));
  end function;

  -- BOOTP reply carrying the message type option and the given
  -- options, closed by the end option.
  function reply(xid: byte_string;
                 msg_type: byte;
                 yiaddr: ipv4_t;
                 options: byte_string) return byte_string
  is
    variable fixed_v: byte_string(0 to options_off_c-1) := (others => x"00");
  begin
    fixed_v(0) := dhcp_op_bootreply_c;
    fixed_v(1) := to_byte(1);
    fixed_v(2) := to_byte(6);
    fixed_v(4 to 7) := xid;
    fixed_v(16 to 19) := yiaddr;
    fixed_v(28 to 33) := client_mac_c;
    fixed_v(cookie_off_c to options_off_c-1) := dhcp_magic_cookie_c;

    return fixed_v
      & opt(dhcp_option_message_type_c, msg_type)
      & options
      & option_end_c;
  end function;

  function lease_options(lease, t1, t2: natural) return byte_string
  is
  begin
    return opt(dhcp_option_server_id_c, server_ip_c)
      & opt(dhcp_option_netmask_c, netmask_c)
      & opt(dhcp_option_router_c, router_c)
      & opt(dhcp_option_dns_c, dns_c)
      & opt32(dhcp_option_lease_time_c, lease)
      & opt32(dhcp_option_renewal_time_c, t1)
      & opt32(dhcp_option_rebinding_time_c, t2);
  end function;

begin

  server: process is
    variable beat_v: master_t;
    variable rx_v: byte_stream;
    variable xid_v, renew_xid_v, last_xid_v: byte_string(0 to 3);
    variable ack_time_v: time;
    variable pos_v: integer;

    procedure tx_get is
    begin
      clear(rx_v);
      loop
        receive(cfg_c, clock_s, tx_s.m, tx_s.s, beat_v);
        for k in 0 to byte_count(cfg_c, beat_v)-1
        loop
          write(rx_v, beat_v.data(k));
        end loop;
        if is_last(cfg_c, beat_v) then
          exit;
        end if;
      end loop;

      assert not is_rejected(cfg_c, beat_v)
        report "Client must not emit rejected packets"
        severity failure;
      assert_equal("tx length", rx_v.all'length, tx_length_c, failure);
    end procedure;

    procedure expect_idle(constant cycles: natural;
                          constant what: string) is
    begin
      for i in 1 to cycles
      loop
        wait until rising_edge(clock_s);
        assert not is_valid(cfg_c, tx_s.m)
          report what
          severity failure;
      end loop;
    end procedure;

    -- Byte of the context block prefix.
    impure function cb(k: integer) return byte is
    begin
      return rx_v.all(k);
    end function;

    impure function cs(f, l: integer) return byte_string is
    begin
      return rx_v.all(f to l);
    end function;

    -- Byte of the DHCP message.
    impure function pb(k: integer) return byte is
    begin
      return rx_v.all(ctx_size_c + k);
    end function;

    impure function ps(f, l: integer) return byte_string is
    begin
      return rx_v.all(ctx_size_c + f to ctx_size_c + l);
    end function;

    -- Offset of the code byte of option code in the message, or -1
    -- when the option is absent.
    impure function opt_at(code: byte) return integer is
      variable i: integer := options_off_c;
    begin
      while i < payload_length_c
      loop
        if pb(i) = dhcp_option_pad_c then
          i := i + 1;
        elsif pb(i) = dhcp_option_end_c then
          return -1;
        elsif pb(i) = code then
          return i;
        else
          i := i + 2 + to_integer(unsigned(pb(i+1)));
        end if;
      end loop;

      return -1;
    end function;

    -- Checks the parts shared by every message the client emits, and
    -- returns the offset of the message type option.
    impure function check_common(constant what: string) return integer is
      variable o: integer;
    begin
      assert_equal(what & " udp peer port",
                   to_integer(from_be(cs(ip_context_length_c,
                                         ip_context_length_c+1))),
                   dhcp_server_port_c, failure);
      assert_equal(what & " ip length",
                   to_integer(from_be(cs(5, 6))),
                   udp_header_length_c + payload_length_c, failure);
      assert_equal(what & " op", pb(0), dhcp_op_bootrequest_c, failure);
      assert_equal(what & " htype", pb(1), to_byte(1), failure);
      assert_equal(what & " hlen", pb(2), to_byte(6), failure);
      assert_equal(what & " chaddr", ps(28, 43),
                   client_mac_c & chaddr_pad_c, failure);
      assert_equal(what & " cookie", ps(cookie_off_c, options_off_c-1),
                   dhcp_magic_cookie_c, failure);

      o := opt_at(dhcp_option_client_id_c);
      assert o >= 0
        report what & ": client id option is missing"
        severity failure;
      assert_equal(what & " client id", ps(o+2, o+8),
                   to_byte(1) & client_mac_c, failure);

      assert opt_at(dhcp_option_parameter_request_c) >= 0
        report what & ": parameter request list is missing"
        severity failure;

      assert opt_at(dhcp_option_hostname_c) >= 0
        report what & ": host name option is missing"
        severity failure;
      o := opt_at(dhcp_option_hostname_c);
      assert_equal(what & " host name", ps(o+2, o+1+hostname_c'length),
                   to_byte_string(hostname_c), failure);

      o := opt_at(dhcp_option_message_type_c);
      assert o >= 0
        report what & ": message type option is missing"
        severity failure;
      return o;
    end function;
  begin
    tx_s.s <= accept(cfg_c, false);
    rx_s.m <= transfer_defaults(cfg_c);
    wait for 100 ns;

    -- Discovery
    tx_get;
    pos_v := check_common("discover");
    assert_equal("discover message type", pb(pos_v+2),
                 dhcp_msg_discover_c, failure);
    assert_equal("discover ip peer", cs(0, 3), broadcast_ip_c, failure);
    assert_equal("discover ip casting", cb(4), to_byte(1), failure);
    assert_equal("discover flags", ps(10, 11), from_hex("8000"), failure);
    assert_equal("discover ciaddr", ps(12, 15), any_ip_c, failure);
    assert opt_at(dhcp_option_requested_address_c) < 0
      report "Discovery must not carry a requested address"
      severity failure;
    xid_v := ps(4, 7);

    -- An offer for another transaction must not be taken
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(not xid_v, dhcp_msg_offer_c,
                                           decoy_ip_c,
                                           lease_options(60, 30, 50)),
                user => "0");
    expect_idle(400, "Offer with a foreign xid must be ignored");

    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(xid_v, dhcp_msg_offer_c,
                                           client_ip_c,
                                           opt(dhcp_option_server_id_c,
                                               server_ip_c)),
                user => "0");

    -- Selection
    tx_get;
    pos_v := check_common("request");
    assert_equal("request message type", pb(pos_v+2),
                 dhcp_msg_request_c, failure);
    assert_equal("request xid", ps(4, 7), xid_v, failure);
    assert_equal("request ip peer", cs(0, 3), broadcast_ip_c, failure);
    assert_equal("request ip casting", cb(4), to_byte(1), failure);
    assert_equal("request flags", ps(10, 11), from_hex("8000"), failure);
    assert_equal("request ciaddr", ps(12, 15), any_ip_c, failure);
    pos_v := opt_at(dhcp_option_requested_address_c);
    assert pos_v >= 0
      report "Selecting request must carry the requested address"
      severity failure;
    assert_equal("request requested address", ps(pos_v+2, pos_v+5),
                 client_ip_c, failure);
    pos_v := opt_at(dhcp_option_server_id_c);
    assert pos_v >= 0
      report "Selecting request must carry the server id"
      severity failure;
    assert_equal("request server id", ps(pos_v+2, pos_v+5),
                 server_ip_c, failure);

    -- Binding, with neither renewal nor rebinding time, so that the
    -- renewal point falls at half the lease
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(xid_v, dhcp_msg_ack_c, client_ip_c,
                                           opt(dhcp_option_server_id_c,
                                               server_ip_c)
                                           & opt(dhcp_option_netmask_c,
                                                 netmask_c)
                                           & opt(dhcp_option_router_c,
                                                 router_c)
                                           & opt(dhcp_option_dns_c, dns_c)
                                           & opt32(dhcp_option_lease_time_c,
                                                   20)),
                user => "0");
    ack_time_v := now;

    wait until valid_s = '1' for 5 * tick_c;
    assert_equal("lease acquired", valid_s, '1', failure);
    assert_equal("address", address_s, client_ip_c, failure);
    assert_equal("netmask", netmask_s, netmask_c, failure);
    assert_equal("router", router_s, router_c, failure);
    assert_equal("dns", dns_s, dns_c, failure);

    -- Renewal
    tx_get;
    assert now - ack_time_v > 8 * tick_c and now - ack_time_v < 15 * tick_c
      report "Renewal must happen around half the lease"
      severity failure;
    pos_v := check_common("renew");
    assert_equal("renew message type", pb(pos_v+2),
                 dhcp_msg_request_c, failure);
    assert_equal("renew ip peer", cs(0, 3), server_ip_c, failure);
    assert_equal("renew ip casting", cb(4), to_byte(0), failure);
    assert_equal("renew flags", ps(10, 11), from_hex("0000"), failure);
    assert_equal("renew ciaddr", ps(12, 15), client_ip_c, failure);
    assert opt_at(dhcp_option_requested_address_c) < 0
      report "Renewal must not carry a requested address"
      severity failure;
    assert opt_at(dhcp_option_server_id_c) < 0
      report "Renewal must not carry a server id"
      severity failure;
    assert_different("renew xid", ps(4, 7), xid_v, failure);
    renew_xid_v := ps(4, 7);

    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(renew_xid_v, dhcp_msg_ack_c,
                                           client_ip_c,
                                           lease_options(200, 20, 180)),
                user => "0");
    wait for 2 us;
    assert_equal("lease held after renewal", valid_s, '1', failure);
    assert_equal("address after renewal", address_s, client_ip_c, failure);

    -- A rejected reply carries no information
    tx_get;
    pos_v := check_common("renew2");
    assert_equal("renew2 ip casting", cb(4), to_byte(0), failure);
    renew_xid_v := ps(4, 7);

    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(renew_xid_v, dhcp_msg_ack_c,
                                           decoy_ip_c,
                                           opt(dhcp_option_server_id_c,
                                               server_ip_c)
                                           & opt(dhcp_option_netmask_c,
                                                 decoy_netmask_c)
                                           & opt32(dhcp_option_lease_time_c,
                                                   200)),
                user => "1");
    wait for 2 us;
    assert_equal("lease held after rejected ack", valid_s, '1', failure);
    assert_equal("address after rejected ack", address_s, client_ip_c,
                 failure);
    assert_equal("netmask after rejected ack", netmask_s, netmask_c, failure);

    -- The transaction is still the same one, so the client is
    -- retransmitting rather than renewing a refreshed lease
    tx_get;
    pos_v := check_common("renew retry");
    assert_equal("renew retry xid", ps(4, 7), renew_xid_v, failure);
    assert_equal("renew retry ip casting", cb(4), to_byte(0), failure);

    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(renew_xid_v, dhcp_msg_ack_c,
                                           client_ip_c,
                                           lease_options(200, 20, 180)),
                user => "0");
    wait for 2 us;
    assert_equal("lease held after retry", valid_s, '1', failure);
    assert_equal("netmask after retry", netmask_s, netmask_c, failure);

    -- Refusal of a renewal drops the lease and restarts discovery
    tx_get;
    pos_v := check_common("renew3");
    last_xid_v := ps(4, 7);

    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(last_xid_v, dhcp_msg_nak_c,
                                           any_ip_c,
                                           opt(dhcp_option_server_id_c,
                                               server_ip_c)),
                user => "0");

    wait until valid_s = '0' for 5 * tick_c;
    assert_equal("lease dropped", valid_s, '0', failure);
    assert_equal("address dropped", address_s, any_ip_c, failure);
    assert_equal("netmask dropped", netmask_s, any_ip_c, failure);
    assert_equal("router dropped", router_s, any_ip_c, failure);
    assert_equal("dns dropped", dns_s, any_ip_c, failure);

    tx_get;
    pos_v := check_common("rediscover");
    assert_equal("rediscover message type", pb(pos_v+2),
                 dhcp_msg_discover_c, failure);
    assert_equal("rediscover flags", ps(10, 11), from_hex("8000"), failure);
    assert_equal("rediscover ciaddr", ps(12, 15), any_ip_c, failure);
    assert_different("rediscover xid", ps(4, 7), last_xid_v, failure);

    log_info("DHCP client OK");
    done_s(0) <= '1';
    wait;
  end process;

  -- The client without a host name
  anonymous: process is
    variable beat_v: master_t;
    variable rx_v: byte_stream;
    variable i_v: integer;
  begin
    tx2_s.s <= accept(cfg_c, false);
    rx2_s.m <= transfer_defaults(cfg_c);
    wait for 100 ns;

    clear(rx_v);
    loop
      receive(cfg_c, clock_s, tx2_s.m, tx2_s.s, beat_v);
      for k in 0 to byte_count(cfg_c, beat_v)-1
      loop
        write(rx_v, beat_v.data(k));
      end loop;
      if is_last(cfg_c, beat_v) then
        exit;
      end if;
    end loop;

    assert_equal("anonymous tx length", rx_v.all'length, tx_length_c, failure);

    i_v := options_off_c;
    while i_v < payload_length_c
    loop
      assert rx_v.all(ctx_size_c + i_v) /= dhcp_option_hostname_c
        report "Client with no host name must not send the host name option"
        severity failure;

      if rx_v.all(ctx_size_c + i_v) = dhcp_option_pad_c then
        i_v := i_v + 1;
      elsif rx_v.all(ctx_size_c + i_v) = dhcp_option_end_c then
        exit;
      else
        i_v := i_v + 2 + to_integer(unsigned(rx_v.all(ctx_size_c + i_v + 1)));
      end if;
    end loop;

    log_info("Anonymous DHCP client OK");
    done_s(1) <= '1';
    wait;
  end process;

  watchdog: process is
  begin
    wait for 600 us;
    assert false
      report "Simulation did not complete in time"
      severity failure;
    wait;
  end process;

  dut: nsl_inet.stream_dhcp.stream_dhcp_client
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => client_hz_c,
      hostname_c => hostname_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      enable_i => '1',
      hwaddr_i => client_mac_c,

      rx_i => rx_s.m,
      rx_o => rx_s.s,
      tx_o => tx_s.m,
      tx_i => tx_s.s,

      address_o => address_s,
      netmask_o => netmask_s,
      router_o => router_s,
      dns_o => dns_s,
      valid_o => valid_s
      );

  dut_anonymous: nsl_inet.stream_dhcp.stream_dhcp_client
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => client_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      enable_i => '1',
      hwaddr_i => client_mac_c,

      rx_i => rx2_s.m,
      rx_o => rx2_s.s,
      tx_o => tx2_s.m,
      tx_i => tx2_s.s,

      address_o => address2_s,
      netmask_o => netmask2_s,
      router_o => router2_s,
      dns_o => dns2_s,
      valid_o => valid2_s
      );

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
