library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_inet.vlan.all;

-- One tagged layer-1 committed link fanned out to one committed pipe
-- per VLAN.
--
-- RX (frames the peer sends us, leaving through rx_eth_routed_o):
--
--   rx_eth_vlan_i -> mac_receiver -> vlan_demux -+-> rx_eth_routed_o(0)
--                                                +-> ...      (N-1)
--
-- TX (frames entering through tx_eth_routed_i, leaving towards the peer):
--
--   tx_eth_routed_i(i) -> vlan_mux -> mac_transmitter -> tx_eth_vlan_o
--
-- N is vlan_id_c'length; pipe i carries VID vlan_id_c(i).
--
-- Every port is a committed link: frame bytes, then one status byte
-- flagged last, bit 0 set when the frame is valid. On the per-VID
-- pipes frames are untagged and, by default, carry no FCS; frames whose
-- FCS failed on the way in come out of rx_eth_routed_o with a cancel
-- status.
--
-- With routed_has_fcs_c, the per-VID pipes are layer-1 links too, so a
-- layer-1 driver (RMII, SGMII...) can sit directly on a pipe:
--
--   ... vlan_demux -> mac_transmitter -> rx_eth_routed_o(i)
--   tx_eth_routed_i(i) -> mac_receiver -> vlan_mux ...
--
-- Frames leaving through a pipe are padded to the minimum frame size
-- (removing the tag can take them under it) and get an FCS. Frames
-- entering through a pipe have their FCS checked and stripped; a bad
-- FCS turns into a cancel status, so the frame is dropped before it
-- reaches the link.
--
-- There is no buffering stage: ready propagates end to end between
-- the per-VID pipes and the link, so a stalled pipe stalls the link.
--
-- The *_eth_vlan side carries the layer-1 frame format, FCS included,
-- while vlan_demux and vlan_mux speak the nsl_inet.mac boundary (no
-- FCS). Tag insertion and removal change the frame length, so the FCS
-- is checked and stripped on the way in and recomputed on the way out.

entity vlan_path_router is
  generic(
    -- One committed pipe per entry, in this order.
    vlan_id_c : vlan_id_vector;
    -- Untagged frames belong to this VID.  Default 0 is reserved by
    -- 802.1Q, so untagged frames are dropped unless overridden.
    native_vlan_id_c : vlan_id_t := 0;
    -- Per-VID pipes are layer-1 links instead of stopping at the mac
    -- boundary: an FCS is recomputed on frames leaving through a pipe,
    -- checked and stripped on frames entering it. The link's original
    -- FCS is never forwarded, it covers the tag.
    routed_has_fcs_c : boolean := false
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    -- Tagged layer-1 committed link, FCS present.
    rx_eth_vlan_i : in  committed_req_t;
    rx_eth_vlan_o : out committed_ack_t;

    tx_eth_vlan_o : out committed_req_t;
    tx_eth_vlan_i : in  committed_ack_t;

    -- Per-VID committed pipes, untagged, FCS only with routed_has_fcs_c.
    rx_eth_routed_o : out committed_req_vector(0 to vlan_id_c'length-1);
    rx_eth_routed_i : in  committed_ack_vector(0 to vlan_id_c'length-1);

    tx_eth_routed_i : in  committed_req_vector(0 to vlan_id_c'length-1);
    tx_eth_routed_o : out committed_ack_vector(0 to vlan_id_c'length-1)
    );
end entity;

architecture beh of vlan_path_router is

  -- mac boundary, between the FCS stages and the vlan blocks.
  signal l2_from_mac_s : committed_bus_t;
  signal l2_to_mac_s   : committed_bus_t;

  -- vlan block side of the per-VID pipes, mac boundary (no FCS).
  signal demux_req_s : committed_req_vector(0 to vlan_id_c'length-1);
  signal demux_ack_s : committed_ack_vector(0 to vlan_id_c'length-1);
  signal mux_req_s   : committed_req_vector(0 to vlan_id_c'length-1);
  signal mux_ack_s   : committed_ack_vector(0 to vlan_id_c'length-1);

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

      l1_i => rx_eth_vlan_i,
      l1_o => rx_eth_vlan_o,

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

      l1_o => tx_eth_vlan_o,
      l1_i => tx_eth_vlan_i
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
  -- Per-VID pipes: mac boundary as is, or layer 1 with routed_has_fcs_c
  -- ------------------------------------------------------------------

  pipes: for i in 0 to vlan_id_c'length-1
  generate

    l2_pipe: if not routed_has_fcs_c
    generate
      rx_eth_routed_o(i) <= demux_req_s(i);
      demux_ack_s(i) <= rx_eth_routed_i(i);

      mux_req_s(i) <= tx_eth_routed_i(i);
      tx_eth_routed_o(i) <= mux_ack_s(i);
    end generate;

    l1_pipe: if routed_has_fcs_c
    generate
      -- Pads and appends the FCS on frames leaving through the pipe.
      fcs_append: nsl_inet.mac.mac_transmitter
        generic map(
          l1_has_fcs_c       => true,
          l1_header_length_c => 0,
          min_frame_size_c   => 64
          )
        port map(
          clock_i   => clock_i,
          reset_n_i => reset_n_i,

          l2_i => demux_req_s(i),
          l2_o => demux_ack_s(i),

          l1_o => rx_eth_routed_o(i),
          l1_i => rx_eth_routed_i(i)
          );

      -- Checks and strips the FCS on frames entering through the pipe.
      fcs_check: nsl_inet.mac.mac_receiver
        generic map(
          l1_has_fcs_c       => true,
          l1_header_length_c => 0
          )
        port map(
          clock_i   => clock_i,
          reset_n_i => reset_n_i,

          l1_i => tx_eth_routed_i(i),
          l1_o => tx_eth_routed_o(i),

          l2_o => mux_req_s(i),
          l2_i => mux_ack_s(i)
          );
    end generate;

  end generate;

end architecture;
