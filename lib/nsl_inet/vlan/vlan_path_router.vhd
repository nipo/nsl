library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_inet;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.committed.all;
use nsl_inet.vlan.all;

-- One layer-1 committed link fanned out to one AXI4-Stream pipe per VLAN.
--
-- TX (frames the peer sends us, leaving through routed_tx_o):
--
--   l1_rx_i -> mac_receiver -> vlan_demux -+-> committed_to_axi4_stream -> routed_tx_o(0)
--                                           +-> ...                                  (N-1)
--
-- RX (frames entering through routed_rx_i, leaving towards the peer):
--
--   routed_rx_i(i) -> axi4_stream_to_committed -> vlan_mux -> mac_transmitter -> l1_tx_o
--
-- N is vlan_id_c'length; pipe i carries VID vlan_id_c(i).
--
-- There is no buffering stage: every per-VID pipe is a straight
-- format conversion between the vlan block and the port, so ready
-- propagates end to end and a stalled pipe stalls the link.
--
-- The l1_* side carries the layer-1 frame format, FCS included, while
-- vlan_demux and vlan_mux speak the nsl_inet.mac boundary (no FCS).
-- Tag insertion and removal change the frame length, so the FCS is
-- checked and stripped on the way in and recomputed on the way out.

entity vlan_path_router is
  generic(
    -- One AXI4-Stream pipe per entry, in this order.
    vlan_id_c : vlan_id_vector;
    -- Untagged frames belong to this VID.  Default 0 is reserved by
    -- 802.1Q, so untagged frames are dropped unless overridden.
    native_vlan_id_c : vlan_id_t := 0
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    -- Layer-1 committed link, FCS present.
    l1_rx_i : in  nsl_bnoc.committed.committed_req_t;
    l1_rx_o : out  nsl_bnoc.committed.committed_ack_t;
    l1_tx_o : out nsl_bnoc.committed.committed_req_t;
    l1_tx_i : in nsl_bnoc.committed.committed_ack_t;

    -- Per-VID AXI4-Stream, byte wide with tlast.
    routed_tx_o : out master_vector(0 to vlan_id_c'length-1);
    routed_tx_i : in  slave_vector(0 to vlan_id_c'length-1);

    routed_rx_i : in  master_vector(0 to vlan_id_c'length-1);
    routed_rx_o : out slave_vector(0 to vlan_id_c'length-1)
    );
end entity;

architecture beh of vlan_path_router is

  constant vlan_count_c : natural := vlan_id_c'length;

  -- mac boundary, between the FCS stages and the vlan blocks.
  signal l2_from_mac_s : committed_bus_t;
  signal l2_to_mac_s   : committed_bus_t;

  -- Per-VID committed pipes, vlan blocks to adapters.
  signal demux_req_s : committed_req_array(0 to vlan_count_c-1);
  signal demux_ack_s : committed_ack_array(0 to vlan_count_c-1);
  signal mux_req_s   : committed_req_array(0 to vlan_count_c-1);
  signal mux_ack_s   : committed_ack_array(0 to vlan_count_c-1);

begin

  -- ------------------------------------------------------------------
  -- FCS handling, layer 1 <-> mac boundary
  -- ------------------------------------------------------------------

  -- Checks and strips the FCS before the tag is removed.
  fcs_check: nsl_inet.mac.mac_receiver
    generic map(
      l1_has_fcs_c       => true,
      l1_header_length_c => 0
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      l1_i => l1_rx_i,
      l1_o => l1_rx_o,

      l2_o => l2_from_mac_s.req,
      l2_i => l2_from_mac_s.ack
      );

  -- Pads and recomputes the FCS after the tag has been inserted.
  fcs_append: nsl_inet.mac.mac_transmitter
    generic map(
      l1_has_fcs_c       => true,
      l1_header_length_c => 0,
      min_frame_size_c   => 64
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      l2_i => l2_to_mac_s.req,
      l2_o => l2_to_mac_s.ack,

      l1_o => l1_tx_o,
      l1_i => l1_tx_i
      );

  -- ------------------------------------------------------------------
  -- VLAN routing
  -- ------------------------------------------------------------------

  demux: nsl_inet.vlan.vlan_demux
    generic map(
      header_length_c  => 0,
      vlan_id_c        => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      in_i => l2_from_mac_s.req,
      in_o => l2_from_mac_s.ack,

      vlan_o => demux_req_s,
      vlan_i => demux_ack_s
      );

  mux: nsl_inet.vlan.vlan_mux
    generic map(
      header_length_c  => 0,
      vlan_id_c        => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      vlan_i => mux_req_s,
      vlan_o => mux_ack_s,

      out_o => l2_to_mac_s.req,
      out_i => l2_to_mac_s.ack
      );

  -- ------------------------------------------------------------------
  -- Per-VID stream adaptation
  -- ------------------------------------------------------------------

  per_vlan: for i in 0 to vlan_count_c-1
  generate

    -- TX: committed out of the demux, AXI4-Stream out of the entity.
    tx_adapter: nsl_bnoc.axi_adapter.committed_to_axi4_stream
      port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        committed_i => demux_req_s(i),
        committed_o => demux_ack_s(i),

        axi_o => routed_tx_o(i),
        axi_i => routed_tx_i(i)
        );

    -- RX: AXI4-Stream into the entity, committed into the mux.
    rx_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_committed
      port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        axi_i => routed_rx_i(i),
        axi_o => routed_rx_o(i),

        committed_o => mux_req_s(i),
        committed_i => mux_ack_s(i)
        );

  end generate;

end architecture;
