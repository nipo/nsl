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

-- Stream IPv4 layer test.
--
-- One layer instance per (stream width, forwarded block list) pair,
-- each with two layer-4 pipes (ICMP and UDP).  Every width runs
-- without any forwarded block; two widths also run with a two-block
-- list whose contents are filled with a pattern that must reach the
-- other side untouched, padding included.
--
-- The receive phase feeds packets to the ethernet side: accepted
-- unicast and broadcast packets carrying mac padding to be trimmed,
-- packets rejected for every reason the layer knows, a truncated
-- packet, a packet arriving with the reject flag set, then a burst of
-- minimum-size packets at line rate with a backpressure monitor armed
-- on the ethernet-side input.
--
-- The transmit phase feeds the layer-4 pipes, including a packet
-- whose forwarded and context blocks are the ones extracted from the
-- first received packet, so that the crafted destination address is
-- checked against the source address of that packet.  Every field of
-- the crafted header is checked, the checksum and the identification
-- progression included.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 5;
  constant width_list_c : integer_vector(0 to instance_count_c-1)
    := (1, 2, 4, 2, 4);
  constant blocks_list_c : integer_vector(0 to instance_count_c-1)
    := (0, 0, 0, 1, 1);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c * 3 - 1);

  constant local_c : ipv4_t := to_ipv4(10, 0, 0, 1);
  constant peer_a_c : ipv4_t := to_ipv4(10, 0, 0, 2);
  constant peer_b_c : ipv4_t := to_ipv4(10, 0, 0, 3);
  constant foreign_c : ipv4_t := to_ipv4(10, 0, 0, 9);
  constant limited_broadcast_c : ipv4_t := to_ipv4(255, 255, 255, 255);

  constant proto_list_c : ip_proto_vector(0 to 1)
    := (ip_proto_icmp, ip_proto_udp);
  constant proto_unhandled_c : ip_proto_t := ip_proto_tcp;
  constant ttl_c : integer := 64;

  constant directed_count_c : natural := 14;
  constant linerate_count_c : natural := 24;
  constant rx_count_c : natural := directed_count_c + linerate_count_c;
  -- Largest packet body, IPv4 header, layer-4 PDU and mac padding
  constant max_body_c : natural := 20 + 30 + 26;

  constant tx_count_c : natural := 5;
  -- Index of the transmit packet whose blocks are echoed back from
  -- the receive path
  constant tx_echo_c : natural := 2;

  -- The two-block list mimicks a layer-1 block plus the layer-2
  -- context block; a null list exercises the no-forwarding case.
  function block_lengths(present: integer) return integer_vector
  is
  begin
    if present = 0 then
      return null_integer_vector;
    else
      return integer_vector'(0 => 5, 1 => 7);
    end if;
  end function;

  function rx_destination(idx: integer) return ipv4_t
  is
  begin
    case idx is
      when 1 => return limited_broadcast_c;
      when 6 => return foreign_c;
      when others =>
        if idx >= directed_count_c and idx mod 3 = 0 then
          return limited_broadcast_c;
        else
          return local_c;
        end if;
    end case;
  end function;

  function rx_casting(idx: integer) return ip_casting_t
  is
  begin
    if rx_destination(idx) = limited_broadcast_c then
      return IP_CAST_BROADCAST;
    else
      return IP_CAST_UNICAST;
    end if;
  end function;

  function rx_source(idx: integer) return ipv4_t
  is
  begin
    if idx mod 2 = 0 then
      return peer_a_c;
    else
      return peer_b_c;
    end if;
  end function;

  function rx_proto(idx: integer) return ip_proto_t
  is
  begin
    case idx is
      when 1 => return ip_proto_udp;
      when 4 => return ip_proto_udp;
      when 5 => return ip_proto_udp;
      when 7 => return proto_unhandled_c;
      when 8 => return ip_proto_udp;
      when 11 => return ip_proto_udp;
      when others =>
        if idx >= directed_count_c and idx mod 2 = 1 then
          return ip_proto_udp;
        else
          return ip_proto_icmp;
        end if;
    end case;
  end function;

  function rx_pipe(idx: integer) return natural
  is
  begin
    if rx_proto(idx) = ip_proto_udp then
      return 1;
    else
      return 0;
    end if;
  end function;

  -- Layer-4 PDU bytes actually present in the incoming packet
  function rx_pdu_length(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 20;
      when 1 => return 12;
      when 8 => return 10;
      when 9 => return 18;
      when 10 => return 0;
      when 11 => return 25;
      when others => return 26;
    end case;
  end function;

  -- Layer-4 PDU length the header declares.  Packet 8 declares more
  -- than the stream carries.
  function rx_declared_length(idx: integer) return natural
  is
  begin
    if idx = 8 then
      return 30;
    else
      return rx_pdu_length(idx);
    end if;
  end function;

  -- Total length the header declares.  Packet 13 claims a total
  -- length that does not even cover the header.
  function rx_total_length(idx: integer) return natural
  is
  begin
    if idx = 13 then
      return 8;
    else
      return rx_declared_length(idx) + 20;
    end if;
  end function;

  -- Mac padding bytes appended after the declared end of the packet
  function rx_pad_length(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 6;
      when 1 => return 14;
      when 9 => return 8;
      when 10 => return 26;
      -- Cut and mac padding land in the same beat at the wider widths
      when 11 => return 1;
      when others => return 0;
    end case;
  end function;

  -- Version and IHL byte.  Packet 3 carries options.
  function rx_version_ihl(idx: integer) return byte
  is
  begin
    if idx = 3 then
      return x"46";
    else
      return x"45";
    end if;
  end function;

  -- Flags and fragment offset field.  Packet 4 has more fragments,
  -- packet 5 a non-zero offset, packet 10 the don't fragment flag
  -- alone, which is not a fragmentation marker.
  function rx_fragment(idx: integer) return natural
  is
  begin
    case idx is
      when 4 => return 16#2000#;
      when 5 => return 16#0001#;
      when 10 => return 16#4000#;
      when others => return 0;
    end case;
  end function;

  function rx_corrupt(idx: integer) return boolean
  is
  begin
    return idx = 2;
  end function;

  -- Packet 9 is rejected with mac padding to discard behind the cut,
  -- packet 12 is rejected on a packet whose length is exact.
  function rx_arrives_rejected(idx: integer) return boolean
  is
  begin
    return idx = 9 or idx = 12;
  end function;

  function rx_accepted(idx: integer) return boolean
  is
  begin
    -- Packet 2 has a broken checksum, packet 3 carries options,
    -- packets 4 and 5 are fragments, packet 6 goes to a foreign
    -- address, packet 7 uses a protocol not in the table, packet 13
    -- declares a total length shorter than the header.
    case idx is
      when 2 to 7 => return false;
      when 13 => return false;
      when others => return true;
    end case;
  end function;

  -- A packet is delivered rejected when it arrives rejected or when
  -- its stream ends before the length its header declares.
  function rx_delivered_rejected(idx: integer) return boolean
  is
  begin
    return rx_arrives_rejected(idx)
      or rx_pdu_length(idx) < rx_declared_length(idx);
  end function;

  function rx_pdu(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to rx_pdu_length(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 13 + k * 7 + 5) mod 256);
    end loop;
    return ret;
  end function;

  function rx_padding(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to rx_pad_length(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((16#c3# + k * 5) mod 256);
    end loop;
    return ret;
  end function;

  function rx_header(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to 19) := (others => x"00");
    variable chk: checksum_acc_t := checksum_acc_init_c;
  begin
    ret(ip_off_type_len) := rx_version_ihl(idx);
    ret(ip_off_len_h to ip_off_len_l)
      := to_be(to_unsigned(rx_total_length(idx), 16));
    ret(ip_off_id_h to ip_off_id_l) := to_be(to_unsigned(idx, 16));
    ret(ip_off_off_h to ip_off_off_l)
      := to_be(to_unsigned(rx_fragment(idx), 16));
    ret(ip_off_ttl) := to_byte(ttl_c);
    ret(ip_off_proto) := to_byte(rx_proto(idx));
    ret(ip_off_src0 to ip_off_src3) := rx_source(idx);
    ret(ip_off_dst0 to ip_off_dst3) := rx_destination(idx);

    chk := checksum_update(chk, ret);
    ret(ip_off_chk_h to ip_off_chk_l) := checksum_spill(chk);

    if rx_corrupt(idx) then
      ret(ip_off_chk_h) := ret(ip_off_chk_h) xor x"55";
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

  function tx_peer(idx: integer) return ipv4_t
  is
  begin
    case idx is
      when 0 => return peer_a_c;
      when 1 => return peer_b_c;
      when 3 => return foreign_c;
      when 4 => return limited_broadcast_c;
      -- Context echoed back from the first received packet
      when others => return rx_source(0);
    end case;
  end function;

  -- The casting field is meaningless on transmit, both values must
  -- reach the same crafted header.
  function tx_casting(idx: integer) return ip_casting_t
  is
  begin
    case idx is
      when 0 => return IP_CAST_BROADCAST;
      when others => return IP_CAST_UNICAST;
    end case;
  end function;

  -- Packet 1 carries no PDU at all.  Packet 2 echoes the context of
  -- the first received packet, so its length must match.
  function tx_pdu_length(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 16;
      when 1 => return 0;
      when tx_echo_c => return rx_declared_length(0);
      when 3 => return 1;
      when others => return 8;
    end case;
  end function;

  function tx_pdu(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to tx_pdu_length(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 31 + k * 3 + 17) mod 256);
    end loop;
    return ret;
  end function;

begin

  context_encoding: process is
    variable ctx: ip_context_t;
    variable b: byte_string(0 to ip_context_length_c-1);
  begin
    ctx.peer := to_ipv4(192, 168, 1, 42);
    ctx.casting := IP_CAST_BROADCAST;
    ctx.length := 1234;
    b := to_bytes(ctx);
    assert_equal("broadcast casting byte", b(4), to_byte(1), failure);
    assert_equal("context peer", from_bytes(b).peer, ctx.peer, failure);
    assert_equal("context length", from_bytes(b).length, ctx.length, failure);
    assert from_bytes(b).casting = IP_CAST_BROADCAST
      report "Casting should survive the round trip"
      severity failure;

    ctx.casting := IP_CAST_UNICAST;
    ctx.length := 0;
    b := to_bytes(ctx);
    assert_equal("unicast casting byte", b(4), to_byte(0), failure);
    assert_equal("context length", from_bytes(b).length, 0, failure);
    assert from_bytes(b).casting = IP_CAST_UNICAST
      report "Casting should survive the round trip"
      severity failure;
    wait;
  end process;

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant cfg_c : config_t := stream_config(width_c);
    constant lengths_c : integer_vector := block_lengths(blocks_list_c(inst));
    -- Transported size of the blocks the layer forwards verbatim
    constant pre_c : natural := context_byte_count(cfg_c, lengths_c);
    constant ctx_c : natural
      := context_byte_count(cfg_c, (0 => ip_context_length_c));
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

    signal l3_in_s, l3_out_s : bus_t;
    signal l4_rx_s, l4_tx_s : bus_vector(0 to 1);

    signal monitor_en_s : std_ulogic;
    signal echo_valid_s : std_ulogic;
    signal echo_blocks_s : byte_string(0 to pre_c + ctx_c - 1);

    function rx_wire(idx: integer) return byte_string
    is
    begin
      return pre_pat_c & rx_header(idx) & rx_pdu(idx) & rx_padding(idx);
    end function;

    function rx_expected(idx: integer) return byte_string
    is
      constant ctx_v: ip_context_t
        := (peer => rx_source(idx),
            casting => rx_casting(idx),
            length => rx_declared_length(idx));
      constant kept_c: natural
        := nsl_math.arith.min(rx_pdu_length(idx), rx_declared_length(idx));
      constant pdu_c: byte_string(0 to rx_pdu_length(idx)-1) := rx_pdu(idx);
    begin
      return pre_pat_c & context_pad(cfg_c, to_bytes(ctx_v))
        & pdu_c(0 to kept_c-1);
    end function;

    function tx_packet(idx: integer) return byte_string
    is
      constant ctx_v: ip_context_t
        := (peer => tx_peer(idx),
            casting => tx_casting(idx),
            length => tx_pdu_length(idx));
    begin
      return pre_pat_c & context_pad(cfg_c, to_bytes(ctx_v)) & tx_pdu(idx);
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
            & " packet " & to_string(idx) & ": sparse keep pattern"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          if is_last(cfg_c, beat_v) then
            assert is_rejected(cfg_c, beat_v) = rx_delivered_rejected(idx)
              report name_c & " pipe " & to_string(pipe)
              & " packet " & to_string(idx) & ": unexpected reject flag state"
              severity failure;
            exit;
          end if;
        end loop;

        assert_equal(name_c & " pipe " & to_string(pipe)
                     & " packet " & to_string(idx),
                     rx_v.all, rx_expected(idx), failure);

        if not got_first_v then
          first_blocks := rx_v.all(rx_v.all'left
                                   to rx_v.all'left + pre_c + ctx_c - 1);
          got_first_v := true;
        end if;

        deallocate(rx_v);
      end loop;

      assert got_first_v
        report name_c & " pipe " & to_string(pipe) & ": no packet received"
        severity failure;
    end procedure;

  begin

    l3_stim: process is
      variable packet_v: byte_string(0 to pre_c + max_body_c - 1);
      variable len_v, beats_v, first_v, nbytes_v: integer;
      variable chunk_v: byte_string(0 to cfg_c.data_width-1);
      variable keep_v: std_ulogic_vector(0 to cfg_c.data_width-1);
      variable user_v: std_ulogic_vector(0 to 0);
    begin
      l3_in_s.m <= transfer_defaults(cfg_c);
      monitor_en_s <= '1';
      wait for 200 ns;
      wait until falling_edge(clock_s);

      for idx in 0 to rx_count_c-1
      loop
        len_v := pre_c + 20 + rx_pdu_length(idx) + rx_pad_length(idx);
        packet_v(0 to len_v-1) := rx_wire(idx);
        beats_v := (len_v + width_c - 1) / width_c;

        for b in 0 to beats_v-1
        loop
          first_v := b * width_c;
          nbytes_v := width_c;
          if first_v + nbytes_v > len_v then
            nbytes_v := len_v - first_v;
          end if;

          chunk_v := (others => x"00");
          keep_v := (others => '0');
          for k in 0 to nbytes_v-1
          loop
            chunk_v(k) := packet_v(first_v + k);
            keep_v(k) := '1';
          end loop;

          user_v := "0";
          if b = beats_v-1 and rx_arrives_rejected(idx) then
            user_v := "1";
          end if;

          l3_in_s.m <= transfer(cfg_c,
                                bytes => chunk_v,
                                keep => keep_v,
                                user => user_v,
                                valid => true,
                                last => b = beats_v-1);
          loop
            wait until rising_edge(clock_s);
            exit when is_ready(cfg_c, l3_in_s.s);
          end loop;
          wait until falling_edge(clock_s);
        end loop;

        l3_in_s.m <= transfer_defaults(cfg_c);
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

      pipe_check(0, l4_rx_s(0).m, l4_rx_s(0).s, blocks_v);

      echo_blocks_s <= blocks_v;
      echo_valid_s <= '1';

      log_info(name_c & " receive pipe 0 OK");
      done_s(inst * 3 + 0) <= '1';
      wait;
    end process;

    rx1_check: process is
      variable blocks_v: byte_string(0 to pre_c + ctx_c - 1);
    begin
      pipe_check(1, l4_rx_s(1).m, l4_rx_s(1).s, blocks_v);

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
          packet_send(cfg_c, clock_s, l4_tx_s(0).s, l4_tx_s(0).m,
                      packet => packet, user => "0");
        else
          packet_send(cfg_c, clock_s, l4_tx_s(1).s, l4_tx_s(1).m,
                      packet => packet, user => "0");
        end if;
      end procedure;
    begin
      l4_tx_s(0).m <= transfer_defaults(cfg_c);
      l4_tx_s(1).m <= transfer_defaults(cfg_c);

      wait until echo_valid_s = '1';
      wait until falling_edge(clock_s);

      -- Packets from distinct pipes back to back, the funnel has to
      -- serialize them in offering order.
      for idx in 0 to tx_count_c-1
      loop
        if idx = tx_echo_c then
          tx_send(tx_pipe(idx), echo_blocks_s & tx_pdu(idx));
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
      variable id_v, previous_id_v: integer;

      procedure header_check(constant idx: natural;
                             constant packet: byte_string;
                             variable identification: out integer)
      is
        alias xp: byte_string(0 to packet'length-1) is packet;
        constant header_c: byte_string(0 to 19) := xp(pre_c to pre_c + 19);
        constant what_c: string
          := name_c & " transmit packet " & to_string(idx);
      begin
        assert_equal(what_c & " forwarded blocks",
                     xp(0 to pre_c-1), pre_pat_c, failure);
        assert_equal(what_c & " version and ihl",
                     header_c(ip_off_type_len), to_byte(16#45#), failure);
        assert_equal(what_c & " tos",
                     header_c(ip_off_tos), to_byte(0), failure);
        assert_equal(what_c & " total length",
                     to_integer(from_be(header_c(ip_off_len_h
                                                 to ip_off_len_l))),
                     tx_pdu_length(idx) + 20, failure);
        assert_equal(what_c & " flags and fragment offset",
                     to_integer(from_be(header_c(ip_off_off_h
                                                 to ip_off_off_l))),
                     16#4000#, failure);
        assert_equal(what_c & " ttl",
                     header_c(ip_off_ttl), to_byte(ttl_c), failure);
        assert_equal(what_c & " protocol",
                     header_c(ip_off_proto),
                     to_byte(proto_list_c(tx_pipe(idx))), failure);
        assert_equal(what_c & " source address",
                     header_c(ip_off_src0 to ip_off_src3), local_c, failure);
        assert_equal(what_c & " destination address",
                     header_c(ip_off_dst0 to ip_off_dst3),
                     tx_peer(idx), failure);
        assert checksum_is_valid(header_c)
          report what_c & ": header checksum does not verify"
          severity failure;
        assert_equal(what_c & " pdu",
                     xp(pre_c + 20 to xp'right), tx_pdu(idx), failure);

        identification := to_integer(from_be(header_c(ip_off_id_h
                                                      to ip_off_id_l)));
      end procedure;
    begin
      l3_out_s.s <= accept(cfg_c, false);
      previous_id_v := -1;
      wait for 40 ns;

      for idx in 0 to tx_count_c-1
      loop
        clear(rx_v);
        loop
          receive(cfg_c, clock_s, l3_out_s.m, l3_out_s.s, beat_v);

          assert is_packed(cfg_c, beat_v)
            report name_c & " ethernet output: sparse keep pattern"
            severity failure;

          assert not is_rejected(cfg_c, beat_v)
            report name_c & " ethernet output: unexpected reject flag"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          exit when is_last(cfg_c, beat_v);
        end loop;

        header_check(idx, rx_v.all, id_v);

        if previous_id_v >= 0 then
          assert_equal(name_c & " transmit packet " & to_string(idx)
                       & " identification",
                       id_v, (previous_id_v + 1) mod 65536, failure);
        end if;
        previous_id_v := id_v;

        deallocate(rx_v);
      end loop;

      log_info(name_c & " transmit OK");
      done_s(inst * 3 + 2) <= '1';
      wait;
    end process;

    monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "IP_RX_W" & to_string(width_c) & "_B" & to_string(pre_c),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        enable_i => monitor_en_s,
        bus_i => l3_in_s
        );

    dut: nsl_inet.stream_ipv4.stream_ipv4_layer
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c,
        ip_proto_c => proto_list_c,
        ttl_c => ttl_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_c,

        to_l4_o(0) => l4_rx_s(0).m,
        to_l4_o(1) => l4_rx_s(1).m,
        to_l4_i(0) => l4_rx_s(0).s,
        to_l4_i(1) => l4_rx_s(1).s,

        from_l4_i(0) => l4_tx_s(0).m,
        from_l4_i(1) => l4_tx_s(1).m,
        from_l4_o(0) => l4_tx_s(0).s,
        from_l4_o(1) => l4_tx_s(1).s,

        to_l3_o => l3_out_s.m,
        to_l3_i => l3_out_s.s,
        from_l3_i => l3_in_s.m,
        from_l3_o => l3_in_s.s
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
