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
use nsl_inet.stream_mac.all;
use nsl_inet.stream_ethernet.all;
use nsl_inet.mac.all;

-- Stream ethernet layer test.
--
-- One layer instance per (stream width, forwarded block list) pair,
-- each with two layer-3 pipes (ipv4 and arp).  Every width runs
-- without any forwarded block; the widths whose forwarded block needs
-- tail padding also run with a single 5-byte block, filled with a
-- pattern that must reach the other side untouched, padding included.
--
-- The receive phase feeds frames to the mac side: accepted unicast
-- and broadcast frames, a frame for a foreign address, a frame with
-- an unhandled ethertype, a frame carrying the reject flag, then a
-- burst of minimum-size frames at line rate with a backpressure
-- monitor armed on the mac-side input.
--
-- The transmit phase feeds the layer-3 pipes, including a packet
-- whose forwarded and context blocks are the ones extracted from the
-- first received frame, so that the crafted destination address is
-- checked against the source address of that frame.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 5;
  constant width_list_c : integer_vector(0 to instance_count_c-1)
    := (1, 2, 4, 2, 4);
  constant block_list_c : integer_vector(0 to instance_count_c-1)
    := (0, 0, 0, 5, 5);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c * 3 - 1);

  constant local_c : mac48_t := from_hex("020000000001");
  constant peer_a_c : mac48_t := from_hex("020000000002");
  constant peer_b_c : mac48_t := from_hex("020000000003");
  constant foreign_c : mac48_t := from_hex("0200000000fe");

  constant ethertype_list_c : ethertype_vector(0 to 1)
    := (ethertype_ipv4, ethertype_arp);
  constant ethertype_unhandled_c : ethertype_t := ethertype_ipv6;

  constant directed_count_c : natural := 5;
  constant linerate_count_c : natural := 24;
  constant rx_count_c : natural := directed_count_c + linerate_count_c;
  constant max_payload_c : natural := 60;

  constant tx_count_c : natural := 4;
  -- Index of the transmit packet whose blocks are echoed back from
  -- the receive path
  constant tx_echo_c : natural := 2;

  -- A null list of forwarded blocks for the widths that need no
  -- padding exercise.
  function block_lengths(length: integer) return integer_vector
  is
  begin
    if length = 0 then
      return null_integer_vector;
    else
      return integer_vector'(0 => length);
    end if;
  end function;

  function rx_da(idx: integer) return mac48_t
  is
  begin
    case idx is
      when 1 => return ethernet_broadcast_addr_c;
      when 2 => return foreign_c;
      when others => return local_c;
    end case;
  end function;

  function rx_casting(idx: integer) return l2_casting_t
  is
  begin
    if is_broadcast(rx_da(idx)) then
      return L2_CAST_BROADCAST;
    else
      return L2_CAST_UNICAST;
    end if;
  end function;

  function rx_sa(idx: integer) return mac48_t
  is
  begin
    if idx mod 2 = 0 then
      return peer_a_c;
    else
      return peer_b_c;
    end if;
  end function;

  function rx_ethertype(idx: integer) return ethertype_t
  is
  begin
    if idx = 1 then
      return ethertype_arp;
    elsif idx = 3 then
      return ethertype_unhandled_c;
    elsif idx >= directed_count_c and idx mod 2 = 1 then
      return ethertype_arp;
    else
      return ethertype_ipv4;
    end if;
  end function;

  -- Frame 0 is longer than the minimum size, every other frame is a
  -- minimum-size frame, mac padding included.
  function rx_payload_length(idx: integer) return natural
  is
  begin
    if idx = 0 then
      return max_payload_c;
    else
      return 46;
    end if;
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

  function rx_rejected(idx: integer) return boolean
  is
  begin
    return idx = 4;
  end function;

  function rx_accepted(idx: integer) return boolean
  is
  begin
    -- Frame 2 goes to a foreign address, frame 3 carries an
    -- ethertype not in the table.
    return idx /= 2 and idx /= 3;
  end function;

  function rx_pipe(idx: integer) return natural
  is
  begin
    if rx_ethertype(idx) = ethertype_arp then
      return 1;
    else
      return 0;
    end if;
  end function;

  function tx_pipe(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return 1;
      when 3 => return 1;
      when others => return 0;
    end case;
  end function;

  function tx_peer(idx: integer) return mac48_t
  is
  begin
    case idx is
      when 0 => return peer_b_c;
      when 1 => return peer_a_c;
      when 3 => return ethernet_broadcast_addr_c;
      -- Context echoed back from the first received frame
      when others => return rx_sa(0);
    end case;
  end function;

  -- The casting field is meaningless on transmit: packet 0 claims
  -- broadcast towards a unicast peer, packet 3 claims unicast towards
  -- the broadcast address.  Both must reach their peer field.
  function tx_casting(idx: integer) return l2_casting_t
  is
  begin
    case idx is
      when 0 => return L2_CAST_BROADCAST;
      when others => return L2_CAST_UNICAST;
    end case;
  end function;

  -- The pipe a packet is offered on decides its ethertype, the
  -- context has no say in it.
  function tx_ethertype(idx: integer) return ethertype_t
  is
  begin
    return ethertype_list_c(tx_pipe(idx));
  end function;

  function tx_payload(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to 20 + idx * 8 - 1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 31 + k * 3 + 17) mod 256);
    end loop;
    return ret;
  end function;

begin

  context_encoding: process is
    variable ctx: l2_context_t;
    variable b: byte_string(0 to l2_context_length_c-1);
  begin
    ctx.peer := from_hex("0221cafedeca");
    ctx.casting := L2_CAST_BROADCAST;
    b := to_bytes(ctx);
    assert_equal("broadcast casting byte", b(6), to_byte(1), failure);
    assert from_bytes(b).casting = L2_CAST_BROADCAST
      report "Casting should survive the round trip"
      severity failure;

    ctx.casting := L2_CAST_UNICAST;
    b := to_bytes(ctx);
    assert_equal("unicast casting byte", b(6), to_byte(0), failure);
    assert_equal("context peer", from_bytes(b).peer, ctx.peer, failure);
    assert from_bytes(b).casting = L2_CAST_UNICAST
      report "Casting should survive the round trip"
      severity failure;
    wait;
  end process;

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant cfg_c : config_t := stream_config(width_c);
    constant lengths_c : integer_vector := block_lengths(block_list_c(inst));
    -- Transported size of the blocks the layer forwards verbatim
    constant pre_c : natural := context_byte_count(cfg_c, lengths_c);
    constant frame_off_c : natural := ethernet_frame_offset(cfg_c);
    constant frame_pad_c : byte_string(0 to frame_off_c-1) := (others => x"00");
    constant ctx_c : natural
      := context_byte_count(cfg_c, (0 => l2_context_length_c));
    constant ipg_beats_c : natural := 20 / width_c;

    -- Contents of the forwarded block, padding bytes included: the
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

    signal mac_in_s, mac_out_s : bus_t;
    signal l3_rx_s, l3_tx_s : bus_vector(0 to 1);

    signal monitor_en_s : std_ulogic;
    signal echo_valid_s : std_ulogic;
    signal echo_blocks_s : byte_string(0 to pre_c + ctx_c - 1);

    function rx_wire(idx: integer) return byte_string
    is
    begin
      return pre_pat_c & frame_pad_c
        & rx_da(idx) & rx_sa(idx)
        & to_be(to_unsigned(rx_ethertype(idx), 16))
        & rx_payload(idx);
    end function;

    function rx_expected(idx: integer) return byte_string
    is
    begin
      return pre_pat_c
        & context_pad(cfg_c, to_bytes(l2_context_t'(peer => rx_sa(idx),
                                                    casting => rx_casting(idx))))
        & rx_payload(idx);
    end function;

    function tx_packet(idx: integer) return byte_string
    is
    begin
      return pre_pat_c
        & context_pad(cfg_c, to_bytes(l2_context_t'(peer => tx_peer(idx),
                                                    casting => tx_casting(idx))))
        & tx_payload(idx);
    end function;

    function tx_frame(idx: integer) return byte_string
    is
    begin
      return pre_pat_c & frame_pad_c
        & tx_peer(idx) & local_c
        & to_be(to_unsigned(tx_ethertype(idx), 16))
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
            report to_string(cfg_c) & " pipe " & to_string(pipe)
            & " frame " & to_string(idx) & ": sparse keep pattern"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          if is_last(cfg_c, beat_v) then
            assert is_rejected(cfg_c, beat_v) = rx_rejected(idx)
              report to_string(cfg_c) & " pipe " & to_string(pipe)
              & " frame " & to_string(idx) & ": unexpected reject flag state"
              severity failure;
            exit;
          end if;
        end loop;

        assert_equal(to_string(cfg_c) & " blocks " & to_string(pre_c)
                     & " pipe " & to_string(pipe)
                     & " frame " & to_string(idx),
                     rx_v.all, rx_expected(idx), failure);

        if not got_first_v then
          first_blocks := rx_v.all(rx_v.all'left
                                   to rx_v.all'left + pre_c + ctx_c - 1);
          got_first_v := true;
        end if;

        deallocate(rx_v);
      end loop;

      assert got_first_v
        report to_string(cfg_c) & " pipe " & to_string(pipe)
        & ": no frame received"
        severity failure;
    end procedure;

  begin

    mac_stim: process is
      variable frame_v: byte_string(0 to pre_c + frame_off_c
                                    + ethernet_header_length_c
                                    + max_payload_c - 1);
      variable len_v, beats_v, first_v, nbytes_v: integer;
      variable chunk_v: byte_string(0 to cfg_c.data_width-1);
      variable keep_v: std_ulogic_vector(0 to cfg_c.data_width-1);
      variable user_v: std_ulogic_vector(0 to 0);
    begin
      mac_in_s.m <= transfer_defaults(cfg_c);
      monitor_en_s <= '1';
      wait for 200 ns;
      wait until falling_edge(clock_s);

      for idx in 0 to rx_count_c-1
      loop
        len_v := pre_c + frame_off_c + ethernet_header_length_c
                 + rx_payload_length(idx);
        frame_v(0 to len_v-1) := rx_wire(idx);
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
            chunk_v(k) := frame_v(first_v + k);
            keep_v(k) := '1';
          end loop;

          user_v := "0";
          if b = beats_v-1 and rx_rejected(idx) then
            user_v := "1";
          end if;

          mac_in_s.m <= transfer(cfg_c,
                                 bytes => chunk_v,
                                 keep => keep_v,
                                 user => user_v,
                                 valid => true,
                                 last => b = beats_v-1);
          loop
            wait until rising_edge(clock_s);
            exit when is_ready(cfg_c, mac_in_s.s);
          end loop;
          wait until falling_edge(clock_s);
        end loop;

        mac_in_s.m <= transfer_defaults(cfg_c);
        for i in 1 to ipg_beats_c
        loop
          wait until falling_edge(clock_s);
        end loop;
      end loop;

      -- The transmit phase runs afterwards, on other ports
      monitor_en_s <= '0';
      wait;
    end process;

    rx0_check: process is
      variable blocks_v: byte_string(0 to pre_c + ctx_c - 1);
    begin
      echo_valid_s <= '0';
      echo_blocks_s <= (others => x"00");

      pipe_check(0, l3_rx_s(0).m, l3_rx_s(0).s, blocks_v);

      echo_blocks_s <= blocks_v;
      echo_valid_s <= '1';

      log_info(to_string(cfg_c) & " blocks " & to_string(pre_c)
               & " receive pipe 0 OK");
      done_s(inst * 3 + 0) <= '1';
      wait;
    end process;

    rx1_check: process is
      variable blocks_v: byte_string(0 to pre_c + ctx_c - 1);
    begin
      pipe_check(1, l3_rx_s(1).m, l3_rx_s(1).s, blocks_v);

      log_info(to_string(cfg_c) & " blocks " & to_string(pre_c)
               & " receive pipe 1 OK");
      done_s(inst * 3 + 1) <= '1';
      wait;
    end process;

    tx_stim: process is
      procedure tx_send(constant pipe: natural;
                        constant packet: byte_string)
      is
      begin
        if pipe = 0 then
          packet_send(cfg_c, clock_s, l3_tx_s(0).s, l3_tx_s(0).m,
                      packet => packet, user => "0");
        else
          packet_send(cfg_c, clock_s, l3_tx_s(1).s, l3_tx_s(1).m,
                      packet => packet, user => "0");
        end if;
      end procedure;
    begin
      l3_tx_s(0).m <= transfer_defaults(cfg_c);
      l3_tx_s(1).m <= transfer_defaults(cfg_c);

      wait until echo_valid_s = '1';
      wait until falling_edge(clock_s);

      -- Packets from distinct pipes back to back, the funnel has to
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

    mac_out_check: process is
      variable beat_v: master_t;
      variable rx_v: byte_stream;
      variable data_v: byte_string(0 to cfg_c.data_width-1);
      variable da_v: mac48_t;
    begin
      mac_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for idx in 0 to tx_count_c-1
      loop
        clear(rx_v);
        loop
          receive(cfg_c, clock_s, mac_out_s.m, mac_out_s.s, beat_v);

          assert is_packed(cfg_c, beat_v)
            report to_string(cfg_c) & " mac output: sparse keep pattern"
            severity failure;

          data_v := bytes(cfg_c, beat_v);
          for i in 0 to byte_count(cfg_c, beat_v)-1
          loop
            write(rx_v, data_v(i));
          end loop;

          exit when is_last(cfg_c, beat_v);
        end loop;

        assert_equal(to_string(cfg_c) & " blocks " & to_string(pre_c)
                     & " transmit packet " & to_string(idx),
                     rx_v.all, tx_frame(idx), failure);

        if idx = tx_echo_c then
          da_v := rx_v.all(rx_v.all'left + pre_c + frame_off_c
                           to rx_v.all'left + pre_c + frame_off_c + 5);
          assert da_v = rx_sa(0)
            report to_string(cfg_c)
            & ": echoed context does not reach the frame source address"
            severity failure;
        end if;

        deallocate(rx_v);
      end loop;

      log_info(to_string(cfg_c) & " blocks " & to_string(pre_c)
               & " transmit OK");
      done_s(inst * 3 + 2) <= '1';
      wait;
    end process;

    monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "ETH_RX_W" & to_string(width_c) & "_B" & to_string(pre_c),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        enable_i => monitor_en_s,
        bus_i => mac_in_s
        );

    dut: nsl_inet.stream_ethernet.stream_ethernet_layer
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c,
        ethertype_c => ethertype_list_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        local_address_i => local_c,

        to_l3_o(0) => l3_rx_s(0).m,
        to_l3_o(1) => l3_rx_s(1).m,
        to_l3_i(0) => l3_rx_s(0).s,
        to_l3_i(1) => l3_rx_s(1).s,

        from_l3_i(0) => l3_tx_s(0).m,
        from_l3_i(1) => l3_tx_s(1).m,
        from_l3_o(0) => l3_tx_s(0).s,
        from_l3_o(1) => l3_tx_s(1).s,

        to_l1_o => mac_out_s.m,
        to_l1_i => mac_out_s.s,
        from_l1_i => mac_in_s.m,
        from_l1_o => mac_in_s.s
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
