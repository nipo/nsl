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
use nsl_inet.stream_ethernet.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.mac.all;
use nsl_inet.ipv4.all;

-- Stream ARP resolver test.
--
-- One resolver instance per stream width, each driven on its four
-- stream pairs directly: the ethernet-side 0x0806 pipe pair and the
-- resolver query/response pair.  The forwarded block list is a
-- single 5-byte block, so every width exercises block padding; the
-- pattern fed through l1_header_i differs from the one carried by
-- the received frames, so a response or a request built from the
-- wrong source is caught.
--
-- The ethernet transmit side is watched by a monitor process
-- publishing every frame it collects with its timestamp, which lets
-- the stimulus check both frame contents and the absence of traffic.
--
-- The netmask and the gateway are driven by the stimulus: the first
-- half of the script runs with an all-zero netmask, the second half
-- configures a subnet and a gateway and checks the diversion of
-- off-subnet peers.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 3;
  constant width_list_c : integer_vector(0 to instance_count_c-1) := (1, 2, 4);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c-1);

  constant local_mac_c : mac48_t := from_hex("020000000001");
  constant local_ip_c : ipv4_t := to_ipv4(192, 168, 1, 1);

  -- Peer resolved through a request/reply exchange
  constant peer_a_mac_c : mac48_t := from_hex("020000000002");
  constant peer_a_ip_c : ipv4_t := to_ipv4(192, 168, 1, 2);
  -- Peer that never answers
  constant peer_b_ip_c : ipv4_t := to_ipv4(192, 168, 1, 3);
  -- Peer learnt from the request it sends us
  constant peer_c_mac_c : mac48_t := from_hex("020000000004");
  constant peer_c_ip_c : ipv4_t := to_ipv4(192, 168, 1, 4);
  -- Peer whose first reply arrives rejected
  constant peer_d_mac_c : mac48_t := from_hex("020000000005");
  constant peer_d_ip_c : ipv4_t := to_ipv4(192, 168, 1, 5);
  -- Peer requesting somebody else's address
  constant peer_e_mac_c : mac48_t := from_hex("020000000006");
  constant peer_e_ip_c : ipv4_t := to_ipv4(192, 168, 1, 6);
  -- Peer whose request carries mac padding
  constant peer_f_mac_c : mac48_t := from_hex("020000000007");
  constant peer_f_ip_c : ipv4_t := to_ipv4(192, 168, 1, 7);
  -- Peer requesting the local address while a resolution is pending
  constant peer_g_mac_c : mac48_t := from_hex("020000000008");
  constant peer_g_ip_c : ipv4_t := to_ipv4(192, 168, 1, 8);
  -- Address of no interest to the local station
  constant foreign_ip_c : ipv4_t := to_ipv4(192, 168, 1, 9);
  -- On-subnet peer resolved while a gateway is configured
  constant peer_h_mac_c : mac48_t := from_hex("020000000009");
  constant peer_h_ip_c : ipv4_t := to_ipv4(192, 168, 1, 10);

  -- Subnet configuration of the second half of the script, and the
  -- two off-subnet peers reached through the gateway
  constant netmask_c : ipv4_t := to_ipv4(255, 255, 255, 0);
  constant gateway_mac_c : mac48_t := from_hex("02000000000a");
  constant gateway_ip_c : ipv4_t := to_ipv4(192, 168, 1, 254);
  constant remote_a_ip_c : ipv4_t := to_ipv4(10, 0, 0, 1);
  constant remote_b_ip_c : ipv4_t := to_ipv4(10, 1, 2, 3);

  constant mac_zero_c : mac48_t := (others => x"00");
  constant ipv4_zero_c : ipv4_t := (others => x"00");

  constant header_lengths_c : integer_vector(0 to 0) := (0 => 5);
  constant cache_count_l2_c : natural := 2;
  constant timeout_c : natural := 512;
  constant retry_count_c : natural := 2;

  constant arp_pdu_length_c : natural := 28;
  constant oper_request_c : natural := 1;
  constant oper_reply_c : natural := 2;

  -- Mac padding of the shortest ethernet frame carrying an ARP
  -- payload
  constant max_pad_c : natural := 18;
  constant pad_c : byte_string(0 to max_pad_c-1) := (others => x"00");

  function arp_pdu(constant oper: natural;
                   constant sha: mac48_t;
                   constant spa: ipv4_t;
                   constant tha: mac48_t;
                   constant tpa: ipv4_t) return byte_string
  is
  begin
    return from_hex("00010800")
      & to_byte(6) & to_byte(4)
      & to_be(to_unsigned(oper, 16))
      & sha & spa & tha & tpa;
  end function;

begin

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant cfg_c : config_t := stream_config(width_c);
    -- Transported size of the blocks below the ethernet layer
    constant pre_c : natural := context_byte_count(cfg_c, header_lengths_c);
    constant l2_c : natural
      := context_byte_count(cfg_c, (0 => l2_context_length_c));
    constant ip_c : natural
      := context_byte_count(cfg_c, (0 => ip_context_length_c));
    constant tx_len_c : natural := pre_c + l2_c + arp_pdu_length_c;
    constant resp_len_c : natural := pre_c + l2_c + ip_c;

    -- Retry spacing tolerance: the retry timer starts when the
    -- request is handed to the transmit path, the monitor accepts
    -- one beat every other cycle.
    constant spacing_slack_c : natural := 4 * (tx_len_c / width_c) + 32;

    function l1_pattern return byte_string
    is
      variable ret: byte_string(0 to pre_c-1);
    begin
      for k in ret'range
      loop
        ret(k) := to_byte((k * 37 + 16#a5#) mod 256);
      end loop;
      return ret;
    end function;

    function rx_pattern return byte_string
    is
      variable ret: byte_string(0 to pre_c-1);
    begin
      for k in ret'range
      loop
        ret(k) := to_byte((k * 11 + 16#5c#) mod 256);
      end loop;
      return ret;
    end function;

    constant l1_pat_c : byte_string(0 to pre_c-1) := l1_pattern;
    constant rx_pat_c : byte_string(0 to pre_c-1) := rx_pattern;
    constant zero_l2_c : byte_string(0 to l2_c-1) := (others => x"00");

    -- Ethernet-side frame as the ethernet layer would hand it over.
    function rx_frame(constant peer: mac48_t;
                      constant casting: l2_casting_t;
                      constant pdu: byte_string;
                      constant pad: natural) return byte_string
    is
    begin
      return rx_pat_c
        & context_pad(cfg_c, to_bytes(l2_context_t'(peer => peer,
                                                    casting => casting)))
        & pdu & pad_c(0 to pad-1);
    end function;

    -- Query block: the IPv4 context, tail padded with a pattern
    -- rather than zeros, so the verbatim echo of the whole block is
    -- checked.
    function query_block(constant peer: ipv4_t;
                         constant casting: ip_casting_t;
                         constant length: natural;
                         constant tag: natural) return byte_string
    is
      variable ret: byte_string(0 to ip_c-1);
    begin
      ret(0 to ip_context_length_c-1)
        := to_bytes(ip_context_t'(peer => peer,
                                  casting => casting,
                                  length => length));
      for k in ip_context_length_c to ip_c-1
      loop
        ret(k) := to_byte((tag * 7 + k * 29 + 16#3b#) mod 256);
      end loop;
      return ret;
    end function;

    signal from_l2_s, to_l2_s, query_s, response_s : bus_t;
    signal netmask_s, gateway_s : ipv4_t;

    signal wire_count_s : natural;
    signal wire_frame_s : byte_string(0 to tx_len_c-1);
    signal wire_time_s : time;

  begin

    -- Collects every frame the resolver puts on the ethernet side,
    -- publishing contents, arrival time and count.
    wire_monitor: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable data_v: byte_string(0 to cfg_c.data_width-1);
    begin
      to_l2_s.s <= accept(cfg_c, false);
      wire_count_s <= 0;
      wire_frame_s <= (others => x"00");
      wire_time_s <= 0 ns;

      loop
        clear(rx_v);
        loop
          receive(cfg_c, clock_s, to_l2_s.m, to_l2_s.s, beat_v);

          assert is_packed(cfg_c, beat_v)
            report to_string(cfg_c) & " ethernet side: sparse keep pattern"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          exit when is_last(cfg_c, beat_v);
        end loop;

        assert not is_rejected(cfg_c, beat_v)
          report to_string(cfg_c)
          & " ethernet side: emitted frame carries the reject flag"
          severity failure;
        assert_equal(to_string(cfg_c) & " ethernet side frame length",
                     rx_v.all'length, tx_len_c, failure);

        wire_frame_s <= rx_v.all;
        wire_time_s <= now;
        wire_count_s <= wire_count_s + 1;
        deallocate(rx_v);
      end loop;
    end process;

    stim: process is
      variable wire_v: byte_string(0 to tx_len_c-1);
      variable query_v: byte_string(0 to ip_c-1);
      variable stamp_v, request_v, previous_v: time;
      variable taken_v: natural := 0;

      procedure settle(constant cycles: natural) is
      begin
        for i in 1 to cycles
        loop
          wait until falling_edge(clock_s);
        end loop;
      end procedure;

      procedure no_traffic(constant what: string) is
      begin
        settle(64);
        assert_equal(to_string(cfg_c) & " " & what
                     & ": ethernet side frame count",
                     wire_count_s, taken_v, failure);
      end procedure;

      -- Waits for the next frame on the ethernet side and returns
      -- it with its arrival time.  A frame that never comes is a
      -- failure, not a hang.
      procedure wire_get(constant what: string;
                         variable frame: out byte_string;
                         variable stamp: out time) is
        constant deadline_c: time
          := now + (timeout_c * (retry_count_c + 2)) * 10 ns;
      begin
        while wire_count_s < taken_v + 1 and now < deadline_c
        loop
          wait on wire_count_s for deadline_c - now;
        end loop;

        assert wire_count_s >= taken_v + 1
          report to_string(cfg_c) & " " & what
          & ": expected frame never came on the ethernet side"
          severity failure;

        frame := wire_frame_s;
        stamp := wire_time_s;
        taken_v := taken_v + 1;
      end procedure;

      -- Checks the blocks and every ARP payload field of a frame
      -- put on the ethernet side.
      procedure wire_check(constant what: string;
                           constant frame: byte_string;
                           constant peer: mac48_t;
                           constant casting: l2_casting_t;
                           constant oper: natural;
                           constant sha: mac48_t;
                           constant spa: ipv4_t;
                           constant tha: mac48_t;
                           constant tpa: ipv4_t) is
        alias f: byte_string(0 to tx_len_c-1) is frame;
        constant pdu_c: natural := pre_c + l2_c;
        constant label_c: string := to_string(cfg_c) & " " & what;
      begin
        assert_equal(label_c & " l1 blocks",
                     f(0 to pre_c-1), l1_pat_c, failure);
        assert_equal(label_c & " l2 context",
                     f(pre_c to pre_c + l2_c - 1),
                     context_pad(cfg_c,
                                 to_bytes(l2_context_t'(peer => peer,
                                                        casting => casting))),
                     failure);
        assert_equal(label_c & " hardware type",
                     f(pdu_c to pdu_c+1), from_hex("0001"), failure);
        assert_equal(label_c & " protocol type",
                     f(pdu_c+2 to pdu_c+3), from_hex("0800"), failure);
        assert_equal(label_c & " hardware length",
                     f(pdu_c+4), to_byte(6), failure);
        assert_equal(label_c & " protocol length",
                     f(pdu_c+5), to_byte(4), failure);
        assert_equal(label_c & " operation",
                     f(pdu_c+6 to pdu_c+7),
                     to_be(to_unsigned(oper, 16)), failure);
        assert_equal(label_c & " sender hardware address",
                     f(pdu_c+8 to pdu_c+13), sha, failure);
        assert_equal(label_c & " sender protocol address",
                     f(pdu_c+14 to pdu_c+17), spa, failure);
        assert_equal(label_c & " target hardware address",
                     f(pdu_c+18 to pdu_c+23), tha, failure);
        assert_equal(label_c & " target protocol address",
                     f(pdu_c+24 to pdu_c+27), tpa, failure);
      end procedure;

      procedure l2_send(constant frame: byte_string;
                        constant rejected: boolean) is
      begin
        if rejected then
          packet_send(cfg_c, clock_s, from_l2_s.s, from_l2_s.m,
                      packet => frame, user => "1");
        else
          packet_send(cfg_c, clock_s, from_l2_s.s, from_l2_s.m,
                      packet => frame, user => "0");
        end if;
      end procedure;

      procedure query_send(constant block_data: byte_string) is
      begin
        packet_send(cfg_c, clock_s, query_s.s, query_s.m,
                    packet => block_data, user => "0");
      end procedure;

      -- Collects one response, beat per beat, and checks its blocks
      -- and its reject flag.
      procedure response_check(constant what: string;
                               constant peer: mac48_t;
                               constant casting: l2_casting_t;
                               constant rejected: boolean;
                               constant echoed: byte_string) is
        variable beat_v: master_t;
        variable buffer_v: byte_string(0 to resp_len_c-1);
        variable chunk_v: byte_string(0 to cfg_c.data_width-1);
        variable index_v: natural := 0;
        variable rejected_v: boolean := false;
        constant label_c: string := to_string(cfg_c) & " " & what;
      begin
        loop
          receive(cfg_c, clock_s, response_s.m, response_s.s, beat_v);

          assert is_packed(cfg_c, beat_v)
            report label_c & ": sparse keep pattern"
            severity failure;

          chunk_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            assert index_v < resp_len_c
              report label_c & ": response longer than expected"
              severity failure;
            buffer_v(index_v) := chunk_v(i);
            index_v := index_v + 1;
          end loop;

          if is_last(cfg_c, beat_v) then
            rejected_v := is_rejected(cfg_c, beat_v);
            exit;
          end if;

          assert not is_rejected(cfg_c, beat_v)
            report label_c & ": reject flag outside of the last beat"
            severity failure;
        end loop;

        assert_equal(label_c & " length", index_v, resp_len_c, failure);
        assert_equal(label_c & " reject flag", rejected_v, rejected, failure);
        assert_equal(label_c & " l1 blocks",
                     buffer_v(0 to pre_c-1), l1_pat_c, failure);
        if rejected then
          assert_equal(label_c & " l2 context",
                       buffer_v(pre_c to pre_c + l2_c - 1),
                       zero_l2_c, failure);
        else
          assert_equal(label_c & " l2 context",
                       buffer_v(pre_c to pre_c + l2_c - 1),
                       context_pad(cfg_c,
                                   to_bytes(l2_context_t'(peer => peer,
                                                          casting => casting))),
                       failure);
        end if;
        assert_equal(label_c & " query echo",
                     buffer_v(pre_c + l2_c to resp_len_c - 1),
                     echoed, failure);
      end procedure;

    begin
      from_l2_s.m <= transfer_defaults(cfg_c);
      query_s.m <= transfer_defaults(cfg_c);
      response_s.s <= accept(cfg_c, false);
      -- All-zero netmask: every peer is on-link, as if neither input
      -- were connected
      netmask_s <= ipv4_zero_c;
      gateway_s <= ipv4_zero_c;

      wait for 200 ns;
      wait until falling_edge(clock_s);

      -- Unknown peer: a broadcast request goes out, the reply
      -- completes the pending query.
      query_v := query_block(peer_a_ip_c, IP_CAST_UNICAST, 40, 1);
      query_send(query_v);
      wire_get("request for a", wire_v, stamp_v);
      wire_check("request for a", wire_v,
                 ethernet_broadcast_addr_c, L2_CAST_BROADCAST,
                 oper_request_c, local_mac_c, local_ip_c,
                 mac_zero_c, peer_a_ip_c);
      l2_send(rx_frame(peer_a_mac_c, L2_CAST_UNICAST,
                       arp_pdu(oper_reply_c, peer_a_mac_c, peer_a_ip_c,
                               local_mac_c, local_ip_c), 0),
              false);
      response_check("reply-driven response", peer_a_mac_c, L2_CAST_UNICAST,
                     false, query_v);

      -- Same peer again: answered from the cache, without any frame
      query_v := query_block(peer_a_ip_c, IP_CAST_UNICAST, 41, 2);
      query_send(query_v);
      response_check("cached response", peer_a_mac_c, L2_CAST_UNICAST,
                     false, query_v);
      no_traffic("cached response");

      -- Broadcast casting: no lookup, no frame
      query_v := query_block(peer_b_ip_c, IP_CAST_BROADCAST, 42, 3);
      query_send(query_v);
      response_check("broadcast response", ethernet_broadcast_addr_c,
                     L2_CAST_BROADCAST, false, query_v);
      no_traffic("broadcast response");

      -- Peer that never answers: retry_count_c+1 requests, one
      -- timeout apart, then a rejected response
      query_v := query_block(peer_b_ip_c, IP_CAST_UNICAST, 43, 4);
      query_send(query_v);
      for try in 0 to retry_count_c
      loop
        wire_get("request for b " & to_string(try), wire_v, request_v);
        wire_check("request for b " & to_string(try), wire_v,
                   ethernet_broadcast_addr_c, L2_CAST_BROADCAST,
                   oper_request_c, local_mac_c, local_ip_c,
                   mac_zero_c, peer_b_ip_c);

        -- A peer request landing while a resolution is pending gets
        -- its reply through the same transmit path, without
        -- disturbing the retries
        if try = 0 then
          l2_send(rx_frame(peer_g_mac_c, L2_CAST_BROADCAST,
                           arp_pdu(oper_request_c, peer_g_mac_c, peer_g_ip_c,
                                   mac_zero_c, local_ip_c), 0),
                  false);
          wire_get("reply to g", wire_v, stamp_v);
          wire_check("reply to g", wire_v, peer_g_mac_c, L2_CAST_UNICAST,
                     oper_reply_c, local_mac_c, local_ip_c,
                     peer_g_mac_c, peer_g_ip_c);
        end if;

        if try /= 0 then
          assert request_v - previous_v >= timeout_c * 10 ns
            report to_string(cfg_c) & " retry " & to_string(try)
            & " came too early: " & time'image(request_v - previous_v)
            severity failure;
          assert request_v - previous_v
            <= (timeout_c + spacing_slack_c) * 10 ns
            report to_string(cfg_c) & " retry " & to_string(try)
            & " came too late: " & time'image(request_v - previous_v)
            severity failure;
        end if;
        previous_v := request_v;
      end loop;
      response_check("exhausted response", mac_zero_c, L2_CAST_UNICAST,
                     true, query_v);
      no_traffic("exhausted response");

      -- A peer asking for the local address gets a reply, and its
      -- own address is learnt on the way
      l2_send(rx_frame(peer_c_mac_c, L2_CAST_BROADCAST,
                       arp_pdu(oper_request_c, peer_c_mac_c, peer_c_ip_c,
                               mac_zero_c, local_ip_c), 0),
              false);
      wire_get("reply to c", wire_v, stamp_v);
      wire_check("reply to c", wire_v, peer_c_mac_c, L2_CAST_UNICAST,
                 oper_reply_c, local_mac_c, local_ip_c,
                 peer_c_mac_c, peer_c_ip_c);

      query_v := query_block(peer_c_ip_c, IP_CAST_UNICAST, 44, 5);
      query_send(query_v);
      response_check("requester response", peer_c_mac_c, L2_CAST_UNICAST,
                     false, query_v);
      no_traffic("requester response");

      -- A reply arriving with the reject flag teaches nothing
      l2_send(rx_frame(peer_d_mac_c, L2_CAST_UNICAST,
                       arp_pdu(oper_reply_c, peer_d_mac_c, peer_d_ip_c,
                               local_mac_c, local_ip_c), 0),
              true);
      no_traffic("rejected reply");

      query_v := query_block(peer_d_ip_c, IP_CAST_UNICAST, 45, 6);
      query_send(query_v);
      wire_get("request for d", wire_v, stamp_v);
      wire_check("request for d", wire_v,
                 ethernet_broadcast_addr_c, L2_CAST_BROADCAST,
                 oper_request_c, local_mac_c, local_ip_c,
                 mac_zero_c, peer_d_ip_c);
      l2_send(rx_frame(peer_d_mac_c, L2_CAST_UNICAST,
                       arp_pdu(oper_reply_c, peer_d_mac_c, peer_d_ip_c,
                               local_mac_c, local_ip_c), 0),
              false);
      response_check("late response", peer_d_mac_c, L2_CAST_UNICAST,
                     false, query_v);

      -- A request for somebody else is neither answered nor learnt
      l2_send(rx_frame(peer_e_mac_c, L2_CAST_BROADCAST,
                       arp_pdu(oper_request_c, peer_e_mac_c, peer_e_ip_c,
                               mac_zero_c, foreign_ip_c), 0),
              false);
      no_traffic("foreign request");

      query_v := query_block(peer_e_ip_c, IP_CAST_UNICAST, 46, 7);
      query_send(query_v);
      wire_get("request for e", wire_v, stamp_v);
      wire_check("request for e", wire_v,
                 ethernet_broadcast_addr_c, L2_CAST_BROADCAST,
                 oper_request_c, local_mac_c, local_ip_c,
                 mac_zero_c, peer_e_ip_c);
      l2_send(rx_frame(peer_e_mac_c, L2_CAST_UNICAST,
                       arp_pdu(oper_reply_c, peer_e_mac_c, peer_e_ip_c,
                               local_mac_c, local_ip_c), 0),
              false);
      response_check("unlearnt response", peer_e_mac_c, L2_CAST_UNICAST,
                     false, query_v);

      -- Mac padding past the ARP payload changes nothing
      l2_send(rx_frame(peer_f_mac_c, L2_CAST_BROADCAST,
                       arp_pdu(oper_request_c, peer_f_mac_c, peer_f_ip_c,
                               mac_zero_c, local_ip_c), max_pad_c),
              false);
      wire_get("reply to f", wire_v, stamp_v);
      wire_check("reply to f", wire_v, peer_f_mac_c, L2_CAST_UNICAST,
                 oper_reply_c, local_mac_c, local_ip_c,
                 peer_f_mac_c, peer_f_ip_c);

      -- From here on, a subnet and a gateway are configured
      netmask_s <= netmask_c;
      gateway_s <= gateway_ip_c;
      settle(4);

      -- Off-subnet peer: the request goes to the gateway, and the
      -- response carries the gateway hardware address while the
      -- echoed query block still holds the original peer
      query_v := query_block(remote_a_ip_c, IP_CAST_UNICAST, 47, 8);
      query_send(query_v);
      wire_get("request for gateway", wire_v, stamp_v);
      wire_check("request for gateway", wire_v,
                 ethernet_broadcast_addr_c, L2_CAST_BROADCAST,
                 oper_request_c, local_mac_c, local_ip_c,
                 mac_zero_c, gateway_ip_c);
      l2_send(rx_frame(gateway_mac_c, L2_CAST_UNICAST,
                       arp_pdu(oper_reply_c, gateway_mac_c, gateway_ip_c,
                               local_mac_c, local_ip_c), 0),
              false);
      response_check("diverted response", gateway_mac_c, L2_CAST_UNICAST,
                     false, query_v);

      -- Another off-subnet peer hits the very same gateway entry
      query_v := query_block(remote_b_ip_c, IP_CAST_UNICAST, 48, 9);
      query_send(query_v);
      response_check("second diverted response", gateway_mac_c,
                     L2_CAST_UNICAST, false, query_v);
      no_traffic("second diverted response");

      -- An on-subnet peer is still resolved directly
      query_v := query_block(peer_h_ip_c, IP_CAST_UNICAST, 49, 10);
      query_send(query_v);
      wire_get("request for h", wire_v, stamp_v);
      wire_check("request for h", wire_v,
                 ethernet_broadcast_addr_c, L2_CAST_BROADCAST,
                 oper_request_c, local_mac_c, local_ip_c,
                 mac_zero_c, peer_h_ip_c);
      l2_send(rx_frame(peer_h_mac_c, L2_CAST_UNICAST,
                       arp_pdu(oper_reply_c, peer_h_mac_c, peer_h_ip_c,
                               local_mac_c, local_ip_c), 0),
              false);
      response_check("on-subnet response", peer_h_mac_c, L2_CAST_UNICAST,
                     false, query_v);

      no_traffic("end of test");

      log_info(to_string(cfg_c) & " ARP resolver OK");
      done_s(inst) <= '1';
      wait;
    end process;

    -- Any stream that stops moving is a failure, not a hang.
    watchdog: process is
    begin
      wait for 200 us;
      assert done_s(inst) = '1'
        report to_string(cfg_c) & ": test did not complete in time"
        severity failure;
      wait;
    end process;

    dut: nsl_inet.stream_arp.stream_arp_resolver
      generic map(
        config_c => cfg_c,
        header_length_c => header_lengths_c,
        cache_count_l2_c => cache_count_l2_c,
        timeout_c => timeout_c,
        retry_count_c => retry_count_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_hwaddr_i => local_mac_c,
        local_address_i => local_ip_c,
        netmask_i => netmask_s,
        gateway_i => gateway_s,

        l1_header_i => l1_pat_c,

        from_l2_i => from_l2_s.m,
        from_l2_o => from_l2_s.s,
        to_l2_o => to_l2_s.m,
        to_l2_i => to_l2_s.s,

        query_i => query_s.m,
        query_o => query_s.s,

        response_o => response_s.m,
        response_i => response_s.s
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
