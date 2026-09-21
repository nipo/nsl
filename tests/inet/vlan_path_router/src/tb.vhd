library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_simulation;
use nsl_bnoc.committed.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_inet.mac.all;
use nsl_inet.vlan.all;
use nsl_simulation.logging.all;

-- Two-VLAN scenario (VID 10 and 20, no native VLAN, as on mercury-x2),
-- run once per routed_has_fcs_c value:
--
-- - mode 0, routed_has_fcs_c = false: pipes carry untagged frames
--   without FCS (mac boundary).
-- - mode 1, routed_has_fcs_c = true: pipes are layer-1 links, frames
--   leaving a pipe are padded and get an FCS, frames entering a pipe
--   have their FCS checked and stripped.
--
-- Link to pipes: tagged frames with an FCS are played into
-- rx_eth_vlan_i (playing the peer) and checked out on their own
-- rx_eth_routed_o pipe. A last VID 10 frame has a corrupted FCS and
-- must come out with a cancel status.
--
-- Pipes to link: a frame is pushed into each tx_eth_routed_i pipe and
-- checked out on tx_eth_vlan_o, re-tagged for its own VID, padded to
-- 64 bytes with a freshly computed FCS. A last VID 10 frame is bad
-- (cancel status in mode 0, corrupted FCS in mode 1) and must come out
-- with a cancel status.
entity tb is
end entity;

architecture beh of tb is

  constant vlan_id_c        : vlan_id_vector(0 to 1) := (10, 20);
  constant native_vlan_id_c : vlan_id_t := 0;

  constant da_c : mac48_t := from_hex("020000000001");
  constant sa_c : mac48_t := from_hex("020000000002");

  constant vid10_payload_c   : byte_string := from_hex("deadbeef");
  constant vid20_payload_c   : byte_string := from_hex("cafef00d");
  constant vid10_ethertype_c : ethertype_t := 16#1234#;
  constant vid20_ethertype_c : ethertype_t := 16#5678#;

  -- nsl_inet.mac.frame_pack builds a complete untagged L1 frame with
  -- a correct FCS; there is no tagged equivalent, so build one here
  -- the same way, with the 4-byte 802.1Q tag folded into the header
  -- before the FCS is run.
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

  -- Mac boundary format: header without tag, no FCS.
  function untagged_frame_pack(dest, src : mac48_t;
                               ethertype : ethertype_t;
                               payload : byte_string) return byte_string
  is
  begin
    return dest & src & to_be(to_unsigned(ethertype, 16)) & payload;
  end function;

  -- Flips the last FCS byte.
  function fcs_corrupt(frame : byte_string) return byte_string
  is
    variable ret : byte_string(0 to frame'length-1) := frame;
  begin
    ret(ret'right) := not ret(ret'right);
    return ret;
  end function;

  function choose(cond : boolean; t, f : byte_string) return byte_string
  is
  begin
    if cond then
      return t;
    else
      return f;
    end if;
  end function;

  -- Link side, both modes. The peer sends frames exactly payload-sized,
  -- mac_receiver does not care.
  constant vid10_tagged_c : byte_string := tagged_frame_pack(da_c, sa_c, 10, vid10_ethertype_c, vid10_payload_c);
  constant vid20_tagged_c : byte_string := tagged_frame_pack(da_c, sa_c, 20, vid20_ethertype_c, vid20_payload_c);

  -- mac_transmitter enforces the 64-byte minimum on every frame it
  -- sends, however short the pipe frame was.
  constant vid10_tagged_padded_c : byte_string := tagged_frame_pack(da_c, sa_c, 10, vid10_ethertype_c, vid10_payload_c, 64);
  constant vid20_tagged_padded_c : byte_string := tagged_frame_pack(da_c, sa_c, 20, vid20_ethertype_c, vid20_payload_c, 64);

  -- Pipe side, mode 0.
  constant vid10_untagged_c : byte_string := untagged_frame_pack(da_c, sa_c, vid10_ethertype_c, vid10_payload_c);
  constant vid20_untagged_c : byte_string := untagged_frame_pack(da_c, sa_c, vid20_ethertype_c, vid20_payload_c);

  -- Pipe side, mode 1: unpadded with FCS going in, padded with FCS
  -- coming out.
  constant vid10_l1_c        : byte_string := frame_pack(da_c, sa_c, vid10_ethertype_c, vid10_payload_c);
  constant vid20_l1_c        : byte_string := frame_pack(da_c, sa_c, vid20_ethertype_c, vid20_payload_c);
  constant vid10_l1_padded_c : byte_string := frame_pack(da_c, sa_c, vid10_ethertype_c, vid10_payload_c, 64);
  constant vid20_l1_padded_c : byte_string := frame_pack(da_c, sa_c, vid20_ethertype_c, vid20_payload_c, 64);

  constant mode_count_c : natural := 2;
  constant done_per_mode_c : natural := 5;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to mode_count_c * done_per_mode_c - 1);

begin

  modes: for mode in 0 to mode_count_c-1
  generate
    constant has_fcs_c : boolean := mode = 1;

    -- What leaves a pipe for each frame played on the link.
    constant vid10_pipe_out_c : byte_string := choose(has_fcs_c, vid10_l1_padded_c, vid10_untagged_c);
    constant vid20_pipe_out_c : byte_string := choose(has_fcs_c, vid20_l1_padded_c, vid20_untagged_c);
    -- What is pushed into each pipe.
    constant vid10_pipe_in_c : byte_string := choose(has_fcs_c, vid10_l1_c, vid10_untagged_c);
    constant vid20_pipe_in_c : byte_string := choose(has_fcs_c, vid20_l1_c, vid20_untagged_c);
    -- Bad pipe frame: corrupted FCS in mode 1, good bytes with a cancel
    -- status in mode 0.
    constant vid10_pipe_bad_c : byte_string := choose(has_fcs_c, fcs_corrupt(vid10_l1_c), vid10_untagged_c);
    constant vid10_pipe_bad_valid_c : boolean := has_fcs_c;

    constant d0 : natural := mode * done_per_mode_c;
    constant prefix_c : string := "mode " & integer'image(mode) & " ";

    -- Link, split by who drives: link_in_s.req is the peer's frames,
    -- link_out_s.req is the dut's, each .ack is the receiving side.
    signal link_in_s, link_out_s : committed_bus_t;
    -- Pipes: pipe_out_s(i).req leaves the dut, pipe_in_s(i).req enters
    -- it.
    signal pipe_out_s, pipe_in_s : committed_bus_array(0 to 1);
  begin

    -- Link to pipes, stimulus: tagged frames arriving from the peer.
    link_stimulus: process
    begin
      done_s(d0) <= '0';
      link_in_s.req.valid <= '0';
      wait until reset_n_s = '1';
      wait for 100 ns;

      committed_put(link_in_s.req, link_in_s.ack, clock_s,
                    vid10_tagged_c, true, 1, 3);
      committed_put(link_in_s.req, link_in_s.ack, clock_s,
                    vid20_tagged_c, true, 1, 3);
      committed_put(link_in_s.req, link_in_s.ack, clock_s,
                    fcs_corrupt(vid10_tagged_c), true, 1, 3);

      done_s(d0) <= '1';
      wait;
    end process;

    -- Link to pipes, checks: each pipe drains independently.
    pipe_check_vid10: process
    begin
      done_s(d0+1) <= '0';
      pipe_out_s(0).ack.ready <= '0';
      wait until reset_n_s = '1';
      wait for 100 ns;

      committed_check(prefix_c & "rx_eth_routed_o(0) vid10",
                      pipe_out_s(0).req, pipe_out_s(0).ack,
                      clock_s, vid10_pipe_out_c, true, LOG_LEVEL_FATAL, 1, 2);
      committed_check(prefix_c & "rx_eth_routed_o(0) vid10 bad FCS",
                      pipe_out_s(0).req, pipe_out_s(0).ack,
                      clock_s, vid10_pipe_out_c, false, LOG_LEVEL_FATAL, 1, 2);

      done_s(d0+1) <= '1';
      wait;
    end process;

    pipe_check_vid20: process
    begin
      done_s(d0+2) <= '0';
      pipe_out_s(1).ack.ready <= '0';
      wait until reset_n_s = '1';
      wait for 100 ns;

      committed_check(prefix_c & "rx_eth_routed_o(1) vid20",
                      pipe_out_s(1).req, pipe_out_s(1).ack,
                      clock_s, vid20_pipe_out_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(d0+2) <= '1';
      wait;
    end process;

    -- Pipes to link, stimulus. The router does not buffer, so a put
    -- only completes while the link is drained: stimulus and check
    -- must run in separate processes. Frames are pushed one at a time,
    -- so vlan_mux sees them in this order, no arbitration race.
    pipe_stimulus: process
    begin
      done_s(d0+3) <= '0';
      pipe_in_s(0).req.valid <= '0';
      pipe_in_s(1).req.valid <= '0';

      wait until done_s(d0+1) = '1' and done_s(d0+2) = '1';
      wait for 100 ns;

      committed_put(pipe_in_s(0).req, pipe_in_s(0).ack, clock_s,
                    vid10_pipe_in_c, true, 1, 3);
      committed_put(pipe_in_s(1).req, pipe_in_s(1).ack, clock_s,
                    vid20_pipe_in_c, true, 1, 3);
      committed_put(pipe_in_s(0).req, pipe_in_s(0).ack, clock_s,
                    vid10_pipe_bad_c, vid10_pipe_bad_valid_c, 1, 3);

      done_s(d0+3) <= '1';
      wait;
    end process;

    -- Pipes to link, checks.
    link_check: process
    begin
      done_s(d0+4) <= '0';
      link_out_s.ack.ready <= '0';
      wait until reset_n_s = '1';
      wait for 100 ns;

      committed_check(prefix_c & "tx_eth_vlan_o vid10",
                      link_out_s.req, link_out_s.ack, clock_s,
                      vid10_tagged_padded_c, true, LOG_LEVEL_FATAL, 1, 2);
      committed_check(prefix_c & "tx_eth_vlan_o vid20",
                      link_out_s.req, link_out_s.ack, clock_s,
                      vid20_tagged_padded_c, true, LOG_LEVEL_FATAL, 1, 2);
      committed_check(prefix_c & "tx_eth_vlan_o vid10 bad",
                      link_out_s.req, link_out_s.ack, clock_s,
                      vid10_tagged_padded_c, false, LOG_LEVEL_FATAL, 1, 2);

      done_s(d0+4) <= '1';
      wait;
    end process;

    dut: nsl_inet.vlan.vlan_path_router
      generic map(
        vlan_id_c        => vlan_id_c,
        native_vlan_id_c => native_vlan_id_c,
        routed_has_fcs_c => has_fcs_c
        )
      port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        rx_eth_vlan_i => link_in_s.req,
        rx_eth_vlan_o => link_in_s.ack,

        tx_eth_vlan_o => link_out_s.req,
        tx_eth_vlan_i => link_out_s.ack,

        rx_eth_routed_o(0) => pipe_out_s(0).req,
        rx_eth_routed_o(1) => pipe_out_s(1).req,
        rx_eth_routed_i(0) => pipe_out_s(0).ack,
        rx_eth_routed_i(1) => pipe_out_s(1).ack,

        tx_eth_routed_i(0) => pipe_in_s(0).req,
        tx_eth_routed_i(1) => pipe_in_s(1).req,
        tx_eth_routed_o(0) => pipe_in_s(0).ack,
        tx_eth_routed_o(1) => pipe_in_s(1).ack
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
