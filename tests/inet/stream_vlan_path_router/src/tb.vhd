library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.vlan.all;
use nsl_inet.stream_vlan.all;

-- Stream counterpart of the bnoc vlan_path_router test
-- (tests/inet/vlan_path_router), run at every stream width.
--
-- Two VIDs, 10 and 20, neither native.  Tagged frames with an FCS are
-- played into rx_vlan_i and checked out on their own rx_routed_o
-- pipe, untagged and FCS-stripped.  Then an untagged frame is pushed
-- into each tx_routed_i pipe and checked out on tx_vlan_o, re-tagged
-- for its own VID, padded and with a freshly computed FCS.
--
-- Differences with the bnoc test:
--
-- * the stream mac receiver rejects frames under the minimum size, so
--   the tagged frames the peer sends are padded to it, and that mac
--   padding reaches the pipes, the mac layer leaving it to the upper
--   layers to trim;
--
-- * on each direction a bad VID 10 frame follows: a frame with a
--   corrupted FCS from the peer must leave its pipe rejected; a frame
--   rejected on its pipe (corrupted FCS on a layer-1 pipe) must reach
--   the link with a corrupted FCS;
--
-- * instances with routed_has_fcs_c, where pipes are layer-1 streams:
--   frames leave pipes padded with an FCS (the rejected one with an
--   invalid FCS instead of the reject flag) and enter them with one.
--
-- All frames take the layer-1 side geometry of stream_mac: the
-- ethernet frame block front padding precedes the frame bytes.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 5;
  constant width_list_c : integer_vector(0 to instance_count_c-1)
    := (1, 2, 4, 2, 4);
  constant routed_fcs_list_c : integer_vector(0 to instance_count_c-1)
    := (0, 0, 0, 1, 1);
  constant slot_count_c : natural := 3;

  constant vlan_id_c        : vlan_id_vector(0 to 1) := (10, 20);
  constant native_vlan_id_c : vlan_id_t := 0;

  constant da_c : mac48_t := from_hex("020000000001");
  constant sa_c : mac48_t := from_hex("020000000002");

  constant vid10_payload_c   : byte_string := from_hex("deadbeef");
  constant vid20_payload_c   : byte_string := from_hex("cafef00d");
  constant vid10_ethertype_c : ethertype_t := 16#1234#;
  constant vid20_ethertype_c : ethertype_t := 16#5678#;

  -- Smallest legal tagged frame, FCS included
  constant tagged_min_size_c : natural := 64;
  -- Offset of the byte corrupted in the bad FCS frame, in the payload
  constant corrupt_offset_c : natural := 20;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c * slot_count_c - 1);

  -- nsl_inet.mac.frame_pack with the 802.1Q tag folded into the
  -- header before the FCS is run.  min_frame_size_c includes the FCS.
  function tagged_frame_pack(dest, src : mac48_t;
                             vid : vlan_id_t;
                             ethertype : ethertype_t;
                             payload : byte_string;
                             min_frame_size_c : natural := 0) return byte_string
  is
    variable hdr : byte_string(1 to 6 + 6 + 2 + 2 + 2);
    variable fcs : crc_state_t := crc_init(fcs_params_c);
    variable pad : byte_string(payload'length to min_frame_size_c-6-6-2-2-2-4-1) := (others => x"00");
  begin
    hdr(1 to 6) := dest;
    hdr(7 to 12) := src;
    hdr(13 to 14) := to_be(to_unsigned(ethertype_vlan, 16));
    hdr(15 to 16) := to_be(to_unsigned(vid, 16));
    hdr(17 to 18) := to_be(to_unsigned(ethertype, 16));

    fcs := crc_update(fcs_params_c, fcs, hdr);
    fcs := crc_update(fcs_params_c, fcs, payload);
    fcs := crc_update(fcs_params_c, fcs, pad);

    return hdr & payload & pad & crc_spill(fcs_params_c, fcs);
  end function;

  function untagged_frame(dest, src : mac48_t;
                          ethertype : ethertype_t;
                          payload : byte_string) return byte_string
  is
  begin
    return dest & src & to_be(to_unsigned(ethertype, 16)) & payload;
  end function;

  function zeros(length: natural) return byte_string
  is
    constant ret: byte_string(0 to length-1) := (others => x"00");
  begin
    return ret;
  end function;

  function strip_fcs(frame: byte_string) return byte_string
  is
    alias xf: byte_string(0 to frame'length-1) is frame;
  begin
    return xf(0 to xf'length-5);
  end function;

  function corrupted(frame: byte_string; offset: natural) return byte_string
  is
    variable ret: byte_string(0 to frame'length-1) := frame;
  begin
    ret(offset) := ret(offset) xor x"ff";
    return ret;
  end function;

  procedure packet_get(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal stream_i: in master_t;
                       signal stream_o: out slave_t;
                       variable rx: inout byte_stream;
                       variable rejected: out boolean;
                       constant what: string)
  is
    variable beat: master_t;
    variable d: byte_string(0 to cfg.data_width-1);
  begin
    clear(rx);
    loop
      receive(cfg, clock, stream_i, stream_o, beat);

      assert is_packed(cfg, beat)
        report what & ": sparse keep pattern on output"
        severity failure;

      d := bytes(cfg, beat);
      for i in 0 to byte_count(cfg, beat) - 1
      loop
        write(rx, d(i));
      end loop;

      if is_last(cfg, beat) then
        rejected := is_rejected(cfg, beat);
        exit;
      end if;
    end loop;
  end procedure;

  procedure packet_expect(constant cfg: config_t;
                          signal clock: in std_ulogic;
                          signal stream_i: in master_t;
                          signal stream_o: out slave_t;
                          constant expected: byte_string;
                          constant rejected: boolean;
                          constant what: string)
  is
    variable rx: byte_stream;
    variable rejected_v: boolean;
  begin
    packet_get(cfg, clock, stream_i, stream_o, rx, rejected_v, what);
    assert rejected_v = rejected
      report what & ": unexpected reject flag state"
      severity failure;
    assert_equal(what, rx.all, expected, failure);
    deallocate(rx);
  end procedure;

begin

  watchdog: process is
    constant all_done_c : std_ulogic_vector(done_s'range) := (others => '1');
  begin
    wait until done_s = all_done_c for 1 ms;
    assert done_s = all_done_c
      report "Timeout, done: " & to_string(done_s)
      severity failure;
    wait;
  end process;

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant routed_fcs_c : boolean := routed_fcs_list_c(inst) /= 0;
    constant cfg_c : config_t := stream_config(width_c);
    constant offset_c : natural := ethernet_frame_offset(cfg_c);
    constant pad_c : byte_string(0 to offset_c-1) := (others => x"00");

    function instance_name return string
    is
    begin
      if routed_fcs_c then
        return "W" & to_string(width_c) & " routed FCS";
      end if;
      return "W" & to_string(width_c);
    end function;

    constant name_c : string := instance_name;

    -- Length a stream mac transmitter pads a frame to, FCS excluded:
    -- at least the ethernet minimum, then up to the beat boundary.
    function padded_length(length: natural) return natural
    is
      variable ret: natural := length;
    begin
      if ret < 60 then
        ret := 60;
      end if;
      while (ret + offset_c) mod width_c /= 0
      loop
        ret := ret + 1;
      end loop;
      return ret;
    end function;

    -- Tagged frames from the peer, padded to the minimum size
    constant vid10_tagged_c : byte_string
      := tagged_frame_pack(da_c, sa_c, 10, vid10_ethertype_c,
                           vid10_payload_c, tagged_min_size_c);
    constant vid20_tagged_c : byte_string
      := tagged_frame_pack(da_c, sa_c, 20, vid20_ethertype_c,
                           vid20_payload_c, tagged_min_size_c);
    constant vid10_bad_c : byte_string
      := corrupted(vid10_tagged_c, corrupt_offset_c);

    -- The mac padding of the tagged frames, carried to the pipes
    constant rx_pad_c : byte_string
      := zeros(tagged_min_size_c - 4 - 18 - vid10_payload_c'length);

    -- What the demux hands to the pipes: tag and FCS removed, mac
    -- padding kept
    constant vid10_rx_c : byte_string
      := untagged_frame(da_c, sa_c, vid10_ethertype_c, vid10_payload_c & rx_pad_c);
    constant vid20_rx_c : byte_string
      := untagged_frame(da_c, sa_c, vid20_ethertype_c, vid20_payload_c & rx_pad_c);
    constant vid10_bad_rx_c : byte_string
      := corrupted(vid10_rx_c, corrupt_offset_c - 4);

    -- With routed_has_fcs_c, the pipe mac transmitter pads them again
    -- and appends an FCS
    function routed_wire(frame: byte_string) return byte_string
    is
    begin
      return frame_pack(frame_daddr_get(frame), frame_saddr_get(frame),
                        frame_ethertype_get(frame),
                        frame_payload_get(frame),
                        padded_length(frame'length) + 4);
    end function;

    -- Frames the pipes send
    constant vid10_tx_c : byte_string
      := untagged_frame(da_c, sa_c, vid10_ethertype_c, vid10_payload_c);
    constant vid20_tx_c : byte_string
      := untagged_frame(da_c, sa_c, vid20_ethertype_c, vid20_payload_c);

    -- With routed_has_fcs_c, pipes are layer-1 streams: frames carry
    -- an FCS and must be legal, i.e. padded to the minimum size,
    -- padding the pipe mac receiver leaves in place.
    function tx_payload(payload: byte_string) return byte_string
    is
    begin
      if routed_fcs_c then
        return payload & zeros(60 - 14 - payload'length);
      end if;
      return payload;
    end function;

    function tx_wire(ethertype: ethertype_t;
                     payload: byte_string) return byte_string
    is
    begin
      if routed_fcs_c then
        return frame_pack(da_c, sa_c, ethertype, payload, 64);
      end if;
      return untagged_frame(da_c, sa_c, ethertype, payload);
    end function;

    -- Layer-1 pipe frame whose last FCS byte is flipped
    function tx_wire_bad return byte_string
    is
      constant good_c : byte_string
        := tx_wire(vid10_ethertype_c, tx_payload(vid10_payload_c));
    begin
      return corrupted(good_c, good_c'length-1);
    end function;

    -- Expected on tx_vlan_o: tagged, padded, new FCS
    function tx_expected(vid: vlan_id_t;
                         ethertype: ethertype_t;
                         payload: byte_string) return byte_string
    is
      constant p_c : byte_string := tx_payload(payload);
    begin
      return pad_c & tagged_frame_pack(da_c, sa_c, vid, ethertype, p_c,
                                       padded_length(18 + p_c'length) + 4);
    end function;

    signal rx_vlan_s, tx_vlan_s : bus_t;
    signal rx_routed_m_s, tx_routed_m_s : master_vector(0 to 1);
    signal rx_routed_s_s, tx_routed_s_s : slave_vector(0 to 1);
    signal rx_done_s : std_ulogic_vector(0 to 1);
    signal tx_checked_s : natural := 0;

    -- A cancelled frame on a layer-1 stream: the frame bytes as
    -- expected, an FCS that does not verify, no reject flag.
    procedure bad_fcs_expect(signal stream_i: in master_t;
                             signal stream_o: out slave_t;
                             constant expected: byte_string;
                             constant what: string)
    is
      variable rx: byte_stream;
      variable rejected_v: boolean;
    begin
      packet_get(cfg_c, clock_s, stream_i, stream_o, rx, rejected_v, what);
      assert not rejected_v
        report what & ": reject flag set on a layer-1 stream"
        severity failure;
      assert_equal(what, strip_fcs(rx.all), strip_fcs(expected), failure);
      assert not frame_is_fcs_valid(rx.all(rx.all'left + offset_c to rx.all'right))
        report what & ": FCS of a cancelled frame should not verify"
        severity failure;
      deallocate(rx);
    end procedure;

    procedure pipe_expect(signal stream_i: in master_t;
                          signal stream_o: out slave_t;
                          constant expected: byte_string;
                          constant rejected: boolean;
                          constant what: string)
    is
    begin
      if not routed_fcs_c then
        packet_expect(cfg_c, clock_s, stream_i, stream_o,
                      pad_c & expected, rejected, what);
        return;
      end if;

      -- Rejected frames leave a layer-1 pipe with a corrupted FCS
      if not rejected then
        packet_expect(cfg_c, clock_s, stream_i, stream_o,
                      pad_c & routed_wire(expected), false, what);
        return;
      end if;

      bad_fcs_expect(stream_i, stream_o, pad_c & routed_wire(expected), what);
    end procedure;

  begin

    assert frame_is_fcs_valid(vid10_tagged_c)
      and frame_is_fcs_valid(vid20_tagged_c)
      and not frame_is_fcs_valid(vid10_bad_c)
      report "Reference frames are wrong -- test bug"
      severity failure;

    -- Stage 1 stimulus: tagged frames arriving from the peer
    rx_stim: process
    begin
      rx_vlan_s.m <= transfer_defaults(cfg_c);
      wait until reset_n_s = '1';
      wait for 100 ns;
      wait until falling_edge(clock_s);

      packet_send(cfg_c, clock_s, rx_vlan_s.s, rx_vlan_s.m,
                  packet => pad_c & vid10_tagged_c, user => "0");
      packet_send(cfg_c, clock_s, rx_vlan_s.s, rx_vlan_s.m,
                  packet => pad_c & vid20_tagged_c, user => "0");
      packet_send(cfg_c, clock_s, rx_vlan_s.s, rx_vlan_s.m,
                  packet => pad_c & vid10_bad_c, user => "0");
      rx_vlan_s.m <= transfer_defaults(cfg_c);
      wait;
    end process;

    -- Stage 1 checks: each pipe drains independently
    rx_check_vid10: process
    begin
      rx_done_s(0) <= '0';
      rx_routed_s_s(0) <= accept(cfg_c, false);
      wait until reset_n_s = '1';
      wait for 100 ns;

      pipe_expect(rx_routed_m_s(0), rx_routed_s_s(0),
                  vid10_rx_c, false, name_c & " rx_routed_o(0) vid10");
      pipe_expect(rx_routed_m_s(0), rx_routed_s_s(0),
                  vid10_bad_rx_c, true, name_c & " rx_routed_o(0) vid10 bad FCS");

      log_info(name_c & " rx vid10 OK");
      rx_done_s(0) <= '1';
      wait;
    end process;

    rx_check_vid20: process
    begin
      rx_done_s(1) <= '0';
      rx_routed_s_s(1) <= accept(cfg_c, false);
      wait until reset_n_s = '1';
      wait for 100 ns;

      pipe_expect(rx_routed_m_s(1), rx_routed_s_s(1),
                  vid20_rx_c, false, name_c & " rx_routed_o(1) vid20");

      log_info(name_c & " rx vid20 OK");
      rx_done_s(1) <= '1';
      wait;
    end process;

    done_s(inst * slot_count_c + 0) <= rx_done_s(0);
    done_s(inst * slot_count_c + 1) <= rx_done_s(1);

    -- Stage 2, once stage 1 is over: one frame per pipe, the next one
    -- once the previous one got out.
    tx_stim: process
    begin
      tx_routed_m_s(0) <= transfer_defaults(cfg_c);
      tx_routed_m_s(1) <= transfer_defaults(cfg_c);
      wait until rx_done_s = "11";
      wait for 100 ns;
      wait until falling_edge(clock_s);

      packet_send(cfg_c, clock_s, tx_routed_s_s(0), tx_routed_m_s(0),
                  packet => pad_c & tx_wire(vid10_ethertype_c,
                                            tx_payload(vid10_payload_c)),
                  user => "0");
      tx_routed_m_s(0) <= transfer_defaults(cfg_c);
      if tx_checked_s < 1 then
        wait until tx_checked_s = 1;
      end if;
      wait until falling_edge(clock_s);

      packet_send(cfg_c, clock_s, tx_routed_s_s(1), tx_routed_m_s(1),
                  packet => pad_c & tx_wire(vid20_ethertype_c,
                                            tx_payload(vid20_payload_c)),
                  user => "0");
      tx_routed_m_s(1) <= transfer_defaults(cfg_c);
      if tx_checked_s < 2 then
        wait until tx_checked_s = 2;
      end if;
      wait until falling_edge(clock_s);

      -- Bad VID 10 frame: rejected on a mac boundary pipe, with a
      -- corrupted FCS on a layer-1 pipe
      if routed_fcs_c then
        packet_send(cfg_c, clock_s, tx_routed_s_s(0), tx_routed_m_s(0),
                    packet => pad_c & tx_wire_bad,
                    user => "0");
      else
        packet_send(cfg_c, clock_s, tx_routed_s_s(0), tx_routed_m_s(0),
                    packet => pad_c & tx_wire(vid10_ethertype_c,
                                              tx_payload(vid10_payload_c)),
                    user => "1");
      end if;
      tx_routed_m_s(0) <= transfer_defaults(cfg_c);
      wait;
    end process;

    tx_check: process
      constant vid10_expected_c : byte_string
        := tx_expected(10, vid10_ethertype_c, vid10_payload_c);
      constant vid20_expected_c : byte_string
        := tx_expected(20, vid20_ethertype_c, vid20_payload_c);
    begin
      done_s(inst * slot_count_c + 2) <= '0';
      tx_vlan_s.s <= accept(cfg_c, false);

      assert frame_is_fcs_valid(vid10_expected_c(offset_c to vid10_expected_c'right))
        and frame_is_fcs_valid(vid20_expected_c(offset_c to vid20_expected_c'right))
        report "Expected frames have a bad FCS -- test bug"
        severity failure;

      wait until rx_done_s = "11";

      packet_expect(cfg_c, clock_s, tx_vlan_s.m, tx_vlan_s.s,
                    vid10_expected_c, false, name_c & " tx_vlan_o vid10");
      tx_checked_s <= 1;
      packet_expect(cfg_c, clock_s, tx_vlan_s.m, tx_vlan_s.s,
                    vid20_expected_c, false, name_c & " tx_vlan_o vid20");
      tx_checked_s <= 2;
      -- Cancelled frames reach the link with a corrupted FCS
      bad_fcs_expect(tx_vlan_s.m, tx_vlan_s.s,
                     vid10_expected_c, name_c & " tx_vlan_o vid10 bad");

      log_info(name_c & " tx OK");
      done_s(inst * slot_count_c + 2) <= '1';
      wait;
    end process;

    dut: nsl_inet.stream_vlan.stream_vlan_path_router
      generic map(
        config_c         => cfg_c,
        vlan_id_c        => vlan_id_c,
        native_vlan_id_c => native_vlan_id_c,
        routed_has_fcs_c => routed_fcs_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        rx_vlan_i => rx_vlan_s.m,
        rx_vlan_o => rx_vlan_s.s,

        tx_vlan_o => tx_vlan_s.m,
        tx_vlan_i => tx_vlan_s.s,

        rx_routed_o => rx_routed_m_s,
        rx_routed_i => rx_routed_s_s,

        tx_routed_i => tx_routed_m_s,
        tx_routed_o => tx_routed_s_s
        );
  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 100 ns,
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end architecture;
