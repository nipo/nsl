library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data, nsl_inet, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_inet.mac.all;
use nsl_inet.vlan.all;
use nsl_simulation.logging.all;

-- Simple two-VLAN scenario: VID 10 and VID 20 tagged frames are
-- played into l1_rx_i (playing the peer) and checked out on their own
-- routed_tx_o pipe, untagged and FCS-stripped, exactly as
-- vlan_demux/mac_receiver are documented to hand them off. Then an
-- untagged L2 payload is pushed into each routed_rx_i pipe and
-- checked out on l1_tx_o, re-tagged for its own VID with a freshly
-- computed FCS, as vlan_mux/mac_transmitter are documented to produce
-- it.
--
-- Per the real mercury-x2 deployment, neither VID is native
-- (native_vlan_id_c = 0), so every frame is genuinely tagged both
-- directions -- this exercises the tag insertion/removal path, not
-- the untagged passthrough.
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
  -- the same way frame_pack builds its own, just with the extra
  -- 4-byte 802.1Q tag folded into the header before the FCS is run.
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

  -- What vlan_demux/vlan_mux hand off on the per-VID AXI4-Stream
  -- side: the same header minus the 4 tag bytes, no FCS.
  function untagged_frame_pack(dest, src : mac48_t;
                               ethertype : ethertype_t;
                               payload : byte_string) return byte_string
  is
  begin
    return dest & src & to_be(to_unsigned(ethertype, 16)) & payload;
  end function;

  -- Stimulus into l1_rx_i: peer's own business whether it pads, mac_receiver
  -- neither knows nor cares -- send it exactly payload-sized.
  constant vid10_tagged_c   : byte_string := tagged_frame_pack(da_c, sa_c, 10, vid10_ethertype_c, vid10_payload_c);
  constant vid10_untagged_c : byte_string := untagged_frame_pack(da_c, sa_c, vid10_ethertype_c, vid10_payload_c);
  constant vid20_tagged_c   : byte_string := tagged_frame_pack(da_c, sa_c, 20, vid20_ethertype_c, vid20_payload_c);
  constant vid20_untagged_c : byte_string := untagged_frame_pack(da_c, sa_c, vid20_ethertype_c, vid20_payload_c);

  -- Expected out of l1_tx_o: mac_transmitter enforces the 64-byte Ethernet
  -- minimum on every frame it sends, regardless of how short what came
  -- in on routed_rx_i was.
  constant vid10_tagged_padded_c : byte_string := tagged_frame_pack(da_c, sa_c, 10, vid10_ethertype_c, vid10_payload_c, 64);
  constant vid20_tagged_padded_c : byte_string := tagged_frame_pack(da_c, sa_c, 20, vid20_ethertype_c, vid20_payload_c, 64);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 3);

  signal l1_rx_s, l1_tx_s : committed_bus_t;

  -- routed_tx_o/routed_tx_i (demux output, one pipe per VID) and
  -- routed_rx_i/routed_rx_o (mux input) are plain AXI4-Stream, no
  -- ownership-splitting subtlety.
  signal tx_m_s : master_vector(0 to 1);
  signal tx_s_s : slave_vector(0 to 1);
  signal rx_m_s : master_vector(0 to 1);
  signal rx_s_s : slave_vector(0 to 1);

  -- committed-side of the axi4_stream_to_committed/
  -- committed_to_axi4_stream adapters wrapped around each pipe
  signal tx_req_s : committed_req_array(0 to 1);
  signal tx_ack_s : committed_ack_array(0 to 1);
  signal rx_req_s : committed_req_array(0 to 1);
  signal rx_ack_s : committed_ack_array(0 to 1);

begin

  -- Stage 1 stimulus: two tagged frames arriving from the peer.
  stimulus: process
  begin
    done_s(0) <= '0';
    l1_rx_s.req.valid <= '0';
    wait until reset_n_s = '1';
    wait for 100 ns;

    committed_put(l1_rx_s.req, l1_rx_s.ack, clock_s,
                  vid10_tagged_c, true, 1, 3);
    committed_put(l1_rx_s.req, l1_rx_s.ack, clock_s,
                  vid20_tagged_c, true, 1, 3);

    done_s(0) <= '1';
    wait;
  end process;

  -- Stage 1 checks: each pipe drains independently, no coupling
  -- between them expected.
  tx_check_vid10: process
  begin
    done_s(1) <= '0';
    tx_ack_s(0).ready <= '0';
    wait until reset_n_s = '1';
    wait for 100 ns;

    committed_check("routed_tx_o(0) vid10", tx_req_s(0), tx_ack_s(0),
                    clock_s, vid10_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

    done_s(1) <= '1';
    wait;
  end process;

  tx_check_vid20: process
  begin
    done_s(2) <= '0';
    tx_ack_s(1).ready <= '0';
    wait until reset_n_s = '1';
    wait for 100 ns;

    committed_check("routed_tx_o(1) vid20", tx_req_s(1), tx_ack_s(1),
                    clock_s, vid20_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

    done_s(2) <= '1';
    wait;
  end process;

  -- Stage 2, entirely sequential in one process: feed a pipe then
  -- immediately check l1_o for it, rather than racing two independent
  -- processes against vlan_mux's arbiter and guessing its policy.
  mux_check: process
  begin
    done_s(3) <= '0';
    l1_tx_s.ack.ready <= '0';
    rx_req_s(0).valid <= '0';
    rx_req_s(1).valid <= '0';

    wait until done_s(1) = '1' and done_s(2) = '1';
    wait for 100 ns;

    committed_put(rx_req_s(0), rx_ack_s(0), clock_s,
                  vid10_untagged_c, true, 1, 3);
    committed_check("l1_o vid10", l1_tx_s.req, l1_tx_s.ack, clock_s,
                    vid10_tagged_padded_c, true, LOG_LEVEL_FATAL, 1, 2);
    assert frame_is_fcs_valid(vid10_tagged_padded_c)
      report "vid10 reference frame has a bad FCS -- test bug"
      severity failure;

    committed_put(rx_req_s(1), rx_ack_s(1), clock_s,
                  vid20_untagged_c, true, 1, 3);
    committed_check("l1_o vid20", l1_tx_s.req, l1_tx_s.ack, clock_s,
                    vid20_tagged_padded_c, true, LOG_LEVEL_FATAL, 1, 2);
    assert frame_is_fcs_valid(vid20_tagged_padded_c)
      report "vid20 reference frame has a bad FCS -- test bug"
      severity failure;

    done_s(3) <= '1';
    wait;
  end process;

  pipe_adapters: for i in 0 to 1
  generate
    tx_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_committed
      port map(
        clock_i => clock_s, reset_n_i => reset_n_s,

        axi_i => tx_m_s(i), axi_o => tx_s_s(i),

        committed_o => tx_req_s(i),
        committed_i => tx_ack_s(i)
        );

    rx_adapter: nsl_bnoc.axi_adapter.committed_to_axi4_stream
      port map(
        clock_i => clock_s, reset_n_i => reset_n_s,

        committed_i => rx_req_s(i),
        committed_o => rx_ack_s(i),

        axi_o => rx_m_s(i), axi_i => rx_s_s(i)
        );
  end generate;

  dut: nsl_inet.vlan.vlan_path_router
    generic map(
      vlan_id_c        => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i   => clock_s,

      l1_rx_i => l1_rx_s.req,
      l1_rx_o => l1_rx_s.ack,
      l1_tx_o => l1_tx_s.req,
      l1_tx_i => l1_tx_s.ack,

      routed_tx_o => tx_m_s,
      routed_tx_i => tx_s_s,
      routed_rx_i => rx_m_s,
      routed_rx_o => rx_s_s
      );

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
