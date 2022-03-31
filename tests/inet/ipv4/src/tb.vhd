library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_clocking, nsl_inet, nsl_data;
use nsl_simulation.logging.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

architecture arch of tb is

  constant clock_hz_c : natural := 4000;
  constant clock_period_c : time := 1000000000 ns / clock_hz_c;
  constant reset_period_c : time := clock_period_c * 7 / 2;
  
  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  constant ethertype_list_c : ethertype_vector(0 to 1) := (ethertype_ipv4, ethertype_arp);
  constant ip_proto_list_c: ip_proto_vector(0 to 0) := (0 => ip_proto_udp);
  
  signal l1_to_l2_s, l2_to_l1_s : nsl_bnoc.committed.committed_bus;
  signal l2_to_ipv4_s, ipv4_to_l2_s, l2_to_arp_s, arp_to_l2_s,
    l3_to_udp_s, udp_to_l3_s: nsl_bnoc.committed.committed_bus;

  type committed_io is
  record
    inbound, outbound: nsl_bnoc.committed.committed_bus;
  end record;

  signal udp_1234_s, udp_4567_s: committed_io;
  
  signal done_s : std_ulogic_vector(0 to 2);

  constant ate_mac_c : mac48_t := from_hex("020101010102");
  constant ate_ipv4_c : ipv4_t := to_ipv4(10,0,0,2);
  constant null_ipv4_c : ipv4_t := to_ipv4(10,0,0,33);
  constant dut_mac_c : mac48_t := from_hex("deadbeefc001");
  constant dut_ipv4_c : ipv4_t := to_ipv4(10,0,0,1);
  constant gateway_ipv4_c : ipv4_t := to_ipv4(10,0,0,254);
  constant gateway_mac_c : mac48_t := from_hex("fa1efa1efa1e");
  constant netmask_ipv4_c : ipv4_t := to_ipv4(255,255,255,0);
  constant broadcast_ipv4_c : ipv4_t := to_ipv4(10,0,0,255);
  constant foreign_ipv4_c : ipv4_t := to_ipv4(10,0,1,1);
  
  shared variable queue_to_eth, queue_from_eth: committed_queue_root;
  shared variable queue_to_gateway, queue_to_ate: committed_queue_root;
  shared variable queue_to_udp_1234, queue_from_udp_1234: committed_queue_root;
  shared variable queue_to_udp_4567, queue_from_udp_4567: committed_queue_root;

  procedure arp_respond(prefix: string;
                        variable txq: committed_queue_root;
                        payload: byte_string;
                        local_mac: mac48_t;
                        local_ip: ipv4_t) is
  begin
    if from_be(payload(0 to 1)) /= 1 then
      return;
    end if;

    if from_be(payload(2 to 3)) /= 16#0800# then
      return;
    end if;

    if from_be(payload(4 to 4)) /= 6 then
      return;
    end if;

    if from_be(payload(5 to 5)) /= 4 then
      return;
    end if;

    case to_integer(from_be(payload(6 to 7))) is
      when 1 =>
        if payload(24 to 27) = local_ip then
          log_info(prefix&" * ARP   * Replying me");
          committed_queue_put(queue_to_eth,
                              frame_pack(payload(8 to 13), local_mac,
                                         ethertype_arp,
                                         from_hex("0001080006040002")
                                         & local_mac
                                         & local_ip
                                         & payload(8 to 17)), true);
        end if;

      when others =>
        null;
    end case;
  end procedure;
  
begin

  eth_injector: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(queue_to_eth);
    committed_wait(l1_to_l2_s.req, l1_to_l2_s.ack, clock_s, 40);
    while true
    loop
      committed_wait(l1_to_l2_s.req, l1_to_l2_s.ack, clock_s, 64/8);
      committed_queue_get(queue_to_eth, data, valid, clock_period_c);
      ethernet_dump("Net < ", data.all);
      committed_put(l1_to_l2_s.req, l1_to_l2_s.ack, clock_s, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  eth_popper: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(queue_from_eth);
    while true
    loop
      wait for clock_period_c * 96 / 8;
      committed_get(l2_to_l1_s.req, l2_to_l1_s.ack, clock_s, data, valid);
      if not valid then
        log_info("Net * Frame not valid");
        log_info("Net * " & to_string(data.all));
        ethernet_dump("Net * ", data.all);
      else
        ethernet_dump("Net > ", data.all);
      end if;
      committed_queue_put(queue_from_eth, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  udp_1234_injector: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(queue_to_udp_1234);
    committed_wait(udp_1234_s.outbound.req, udp_1234_s.outbound.ack, clock_s, 40);
    while true
    loop
      committed_wait(udp_1234_s.outbound.req, udp_1234_s.outbound.ack, clock_s, 1);
      committed_queue_get(queue_to_udp_1234, data, valid, clock_period_c);
      log_info("UDP:1234 < " & to_string(data.all));
      committed_put(udp_1234_s.outbound.req, udp_1234_s.outbound.ack, clock_s, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  udp_1234_popper: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(queue_from_udp_1234);
    while true
    loop
      committed_get(udp_1234_s.inbound.req, udp_1234_s.inbound.ack, clock_s, data, valid);
      log_info("UDP:1234 > " & to_string(data.all));
      committed_queue_put(queue_from_udp_1234, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  udp_4567_injector: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(queue_to_udp_4567);
    committed_wait(udp_4567_s.outbound.req, udp_4567_s.outbound.ack, clock_s, 40);
    while true
    loop
      committed_wait(udp_4567_s.outbound.req, udp_4567_s.outbound.ack, clock_s, 1);
      committed_queue_get(queue_to_udp_4567, data, valid, clock_period_c);
      log_info("UDP:4567 < " & to_string(data.all));
      committed_put(udp_4567_s.outbound.req, udp_4567_s.outbound.ack, clock_s, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  udp_4567_popper: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(queue_from_udp_4567);
    while true
    loop
      committed_get(udp_4567_s.inbound.req, udp_4567_s.inbound.ack, clock_s, data, valid);
      log_info("UDP:4567 > " & to_string(data.all));
      committed_queue_put(queue_from_udp_4567, data.all, valid);
      deallocate(data);
    end loop;
  end process;
  
  eth_responder: process is
    variable frame : byte_stream;
    variable payload : byte_stream;
    variable valid, broadcast: boolean;
  begin
    while true
    loop
      deallocate(frame);
      deallocate(payload);
      committed_queue_get(queue_from_eth, frame, valid, clock_period_c);

      if not valid then
        next;
      end if;

      if not frame_is_fcs_valid(frame.all) then
        log_info("ETH * FCS not valid");
        next;
      end if;

      broadcast := is_broadcast(frame_daddr_get(frame.all));

      if frame_daddr_get(frame.all) = ate_mac_c then
        committed_queue_put(queue_to_ate, frame.all, true);
      elsif frame_daddr_get(frame.all) = gateway_mac_c then
        committed_queue_put(queue_to_gateway, frame.all, true);
      elsif is_broadcast(frame_daddr_get(frame.all)) then
        committed_queue_put(queue_to_ate, frame.all, true);
        committed_queue_put(queue_to_gateway, frame.all, true);
      else
         log_info("ETH < " & to_string(frame.all) & ", valid: " & to_string(valid));
      end if;
    end loop;
  end process;

  ate_eth: process is
    variable frame : byte_stream;
    variable payload : byte_stream;
    variable valid, broadcast: boolean;
  begin
    committed_queue_init(queue_to_ate);

    wait for 1 ns;

    while true
    loop
      deallocate(frame);
      deallocate(payload);
      committed_queue_get(queue_to_ate, frame, valid, clock_period_c);

      payload := new byte_string(0 to frame'length-18-1);
      payload.all := frame_payload_get(frame.all);

      case frame_ethertype_get(frame.all) is
        when ethertype_arp =>
          arp_respond("ATE  ", queue_to_eth, payload.all, ate_mac_c, ate_ipv4_c);

        when ethertype_ipv4 =>
          log_info("ATE   * IPV4  < " & to_string(payload.all));

        when others =>
          log_info("ATE   * Other < " & to_string(payload.all));
      end case;
    end loop;
    wait;
  end process;

  gateway_eth: process is
    variable frame : byte_stream;
    variable payload : byte_stream;
    variable valid, broadcast: boolean;
  begin
    committed_queue_init(queue_to_gateway);
    while true
    loop
      deallocate(frame);
      deallocate(payload);
      committed_queue_get(queue_to_gateway, frame, valid, clock_period_c);

      payload := new byte_string(0 to frame'length-18-1);
      payload.all := frame_payload_get(frame.all);

      case frame_ethertype_get(frame.all) is
        when ethertype_arp =>
          arp_respond("GW ", queue_to_eth, payload.all, gateway_mac_c, gateway_ipv4_c);

        when others =>
          null;
      end case;
    end loop;
    wait;
  end process;
  
  udp_1234_responder: process is
    variable frame : byte_stream;
    variable payload : byte_stream;
    variable valid, broadcast: boolean;
  begin
    while true
    loop
      deallocate(frame);
      deallocate(payload);
      committed_queue_get(queue_from_udp_1234, frame, valid, clock_period_c);

      if not valid then
        log_info("UDP_1234 * Frame not valid");
        next;
      else
        committed_queue_put(queue_to_udp_1234, frame.all, valid);

      end if;
    end loop;
    wait;
  end process;
  
  udp_4567_responder: process is
    variable frame : byte_stream;
    variable payload : byte_stream;
    variable valid, broadcast: boolean;
  begin
    while true
    loop
      deallocate(frame);
      deallocate(payload);
      committed_queue_get(queue_from_udp_4567, frame, valid, clock_period_c);

      if not valid then
        log_info("UDP_4567 * Frame not valid");
        next;
      else
        committed_queue_put(queue_to_udp_4567, frame.all, valid);

      end if;
    end loop;
    wait;
  end process;

  to_udp: process is
  begin
    done_s(1) <= '0';
    wait for 10 * clock_period_c;

    committed_queue_put(queue_to_eth,
                        frame_pack(dut_mac_c, ate_mac_c,
                                   ethertype_ipv4,
                                   ipv4_pack(dut_ipv4_c,
                                             ate_ipv4_c,
                                             ip_proto_udp,
                                             udp_pack(
                                               1234, 1234,
                                               to_byte_string("Hello, world"))
                                             )), true);

    wait for 300 * clock_period_c;

    committed_queue_put(queue_to_eth,
                        frame_pack(dut_mac_c, ate_mac_c,
                                   ethertype_ipv4,
                                   ipv4_pack(dut_ipv4_c,
                                             ate_ipv4_c,
                                             ip_proto_udp,
                                             udp_pack(
                                               1234, 1234,
                                               to_byte_string("Hello, world"))
                                             )), true);

    for i in 0 to 64
    loop
      wait for 1 sec;
      committed_queue_put(queue_to_eth,
                          frame_pack(dut_mac_c, gateway_mac_c,
                                     ethertype_ipv4,
                                     ipv4_pack(dut_ipv4_c,
                                               to_ipv4(10,0,1,32+(i mod 8)),
                                               ip_proto_udp,
                                               udp_pack(
                                                 4567, i,
                                                 from_hex("dead"))
                                               )), true);
    end loop;

    done_s(1) <= '1';
    wait;
  end process;    
  
  udp_gen: process is
  begin
    done_s(0) <= '0';

    wait for 10 * clock_period_c;

    committed_queue_put(queue_to_udp_1234,
                        ate_ipv4_c & to_byte(0)
                        & to_be(x"0000")
                        & from_hex("deadf00d0000"), true);

    committed_queue_put(queue_to_udp_1234,
                        null_ipv4_c & to_byte(0)
                        & to_be(x"0001")
                        & from_hex("deadf00d0001"), true);

    committed_queue_put(queue_to_udp_1234,
                        foreign_ipv4_c & to_byte(0)
                        & to_be(x"0002")
                        & from_hex("deadf00d0002"), true);

    wait for clock_period_c * 500;

    committed_queue_put(queue_to_udp_1234,
                        foreign_ipv4_c & to_byte(0)
                        & to_be(x"0003")
                        & from_hex("deadf00d0003"), true);

    wait for 10 sec;
    done_s(0) <= '1';
    wait;
  end process;
  
  pinger: process is
  begin
    done_s(2) <= '0';

    wait for 10 * clock_period_c;

    for i in 0 to 31
    loop
      committed_queue_put(queue_to_eth,
                          frame_pack(dut_mac_c, ate_mac_c,
                                     ethertype_ipv4,
                                     ipv4_pack(dut_ipv4_c,
                                               ate_ipv4_c,
                                               ip_proto_icmp,
                                               icmpv4_echo_request_pack(
                                                 i, 0,
                                                 to_byte_string("hello"))
                                               )), true);
      wait for 1 sec;
    end loop;

    wait for 100 ms;
    done_s(2) <= '1';
    wait;
  end process;
  
  eth: nsl_inet.ethernet.ethernet_layer
    generic map(
      ethertype_c => ethertype_list_c,
      l1_header_length_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      local_address_i => dut_mac_c,

      to_l3_o(0) => l2_to_ipv4_s.req,
      to_l3_o(1) => l2_to_arp_s.req,
      to_l3_i(0) => l2_to_ipv4_s.ack,
      to_l3_i(1) => l2_to_arp_s.ack,
      from_l3_i(0) => ipv4_to_l2_s.req,
      from_l3_i(1) => arp_to_l2_s.req,
      from_l3_o(0) => ipv4_to_l2_s.ack,
      from_l3_o(1) => arp_to_l2_s.ack,

      to_l1_o => l2_to_l1_s.req,
      to_l1_i => l2_to_l1_s.ack,
      from_l1_i => l1_to_l2_s.req,
      from_l1_o => l1_to_l2_s.ack
      );

  ipv4: nsl_inet.ipv4.ipv4_layer_ethernet
    generic map(
      l1_header_length_c => 0,
      ip_proto_c => ip_proto_list_c,
      clock_i_hz_c => clock_hz_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      unicast_i => dut_ipv4_c,
      netmask_i => netmask_ipv4_c,
      gateway_i => gateway_ipv4_c,
      hwaddr_i => dut_mac_c,

      to_l4_o(0) => l3_to_udp_s.req,
      to_l4_i(0) => l3_to_udp_s.ack,
      from_l4_i(0) => udp_to_l3_s.req,
      from_l4_o(0) => udp_to_l3_s.ack,

      ip_to_l2_o => ipv4_to_l2_s.req,
      ip_to_l2_i => ipv4_to_l2_s.ack,
      ip_from_l2_i => l2_to_ipv4_s.req,
      ip_from_l2_o => l2_to_ipv4_s.ack,

      arp_to_l2_o => arp_to_l2_s.req,
      arp_to_l2_i => arp_to_l2_s.ack,
      arp_from_l2_i => l2_to_arp_s.req,
      arp_from_l2_o => l2_to_arp_s.ack
      );

  udp: nsl_inet.udp.udp_layer
    generic map(
      tx_mtu_c => 1500,
      udp_port_c => (1234, 4567),
      header_length_c => ipv4_header_length_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      from_L3_i => l3_to_udp_s.req,
      from_L3_o => l3_to_udp_s.ack,
      to_L3_o => udp_to_l3_s.req,
      to_L3_i => udp_to_l3_s.ack,

      to_l5_o(0) => udp_1234_s.inbound.req,
      to_l5_o(1) => udp_4567_s.inbound.req,
      to_l5_i(0) => udp_1234_s.inbound.ack,
      to_l5_i(1) => udp_4567_s.inbound.ack,
      from_l5_i(0) => udp_1234_s.outbound.req,
      from_l5_i(1) => udp_4567_s.outbound.req,
      from_l5_o(0) => udp_1234_s.outbound.ack,
      from_l5_o(1) => udp_4567_s.outbound.ack
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => reset_period_c,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
