library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use work.vlan.all;

-- 802.1Q VLAN tagging for the AXI4-Stream protocol suite, the
-- counterpart of nsl_inet.vlan.  Every component operates on the mac
-- side stream of nsl_inet.stream_mac and returns it, so per-VID
-- branches compose with the ethernet layer, another demux, or another
-- port's mac layer exactly like the bnoc implementation.
--
-- header_length_c lists the contents lengths of the blocks of the
-- layers below, forwarded verbatim.  Below, P stands for
-- nsl_inet.stream.context_byte_count(config_c, header_length_c) and F
-- for nsl_inet.stream_mac.ethernet_frame_offset(config_c).
--
-- Tagged frames
-- =============
--
-- * Forwarded blocks [P]
-- * Ethernet frame block [F+18]:
--   * Front padding [F]
--   * Destination mac address [6]
--   * Source mac address [6]
--   * TPID [2], 0x8100
--   * TCI [2], PCP, DEI and VID
--   * Ethertype [2]
-- * Payload [*]
--
-- Untagged frames
-- ===============
--
-- * Forwarded blocks [P]
-- * Ethernet frame block [F+14]: front padding, addresses, ethertype
-- * Payload [*]
--
-- The tag is 4 bytes long, a whole count of beats at every supported
-- width, so the front padding is the same with or without a tag and
-- the payload starts on a beat boundary in both cases: inserting or
-- removing a tag only rewrites the frame block, the payload flows
-- untouched.
--
-- There is one pipe per configured VID.  Untagged frames belong to
-- the native VLAN: on the demux they are merged, tag-less, into the
-- pipe whose VID matches native_vlan_id_c; on the mux, frames from
-- that pipe are sent without a tag.  If native_vlan_id_c is not part
-- of vlan_id_c, untagged frames are dropped like any unconfigured VID.
-- As VID 0 is reserved by 802.1Q, the default native VLAN drops
-- untagged frames.
--
-- The reject flag of nsl_inet.stream is forwarded unchanged.  Frames
-- are not reordered within a pipe, but untagged frames and frames
-- tagged with the native VID may be reordered relative to each other
-- on the native pipe, as they take distinct paths in the demux.
--
-- Priority tagging is not supported: PCP and DEI are discarded on
-- receive and transmitted as zero.
package stream_vlan is

  constant vlan_tag_length_c : natural := 4;

  -- Index of vid in vlan_id, -1 if absent.  When vid appears more
  -- than once, the first entry wins.
  function vlan_index(vlan_id: vlan_id_vector;
                      vid: vlan_id_t) return integer;

  -- Routes frames on their 802.1Q tag.  Tagged frames matching a
  -- configured VID have TPID and TCI removed and go to the matching
  -- out_o pipe.  Untagged frames go, untouched, to the pipe matching
  -- native_vlan_id_c.  Other frames, including frames too short to
  -- carry the header they claim, are dropped.
  --
  -- Removing bytes only, the demux honors the backpressure contract
  -- of nsl_inet.stream on its input.
  component stream_vlan_demux is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      vlan_id_c : vlan_id_vector;
      native_vlan_id_c : vlan_id_t := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to vlan_id_c'length-1);
      out_i : in slave_vector(0 to vlan_id_c'length-1)
      );
  end component;

  -- Merges per-VID pipes to a single stream.  Frames get TPID and TCI
  -- inserted after the source address, with the VID of their pipe,
  -- except frames of the pipe matching native_vlan_id_c, which are
  -- forwarded untouched.
  component stream_vlan_mux is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      vlan_id_c : vlan_id_vector;
      native_vlan_id_c : vlan_id_t := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_vector(0 to vlan_id_c'length-1);
      in_o : out slave_vector(0 to vlan_id_c'length-1);

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- One tagged layer-1 link fanned out to one pipe pair per VLAN.
  --
  -- RX (frames the peer sends, leaving through rx_routed_o):
  --
  --   rx_vlan_i -> stream_mac_receiver -> stream_vlan_demux -> rx_routed_o
  --
  -- TX (frames entering through tx_routed_i, leaving towards the peer):
  --
  --   tx_routed_i -> stream_vlan_mux -> stream_mac_transmitter -> tx_vlan_o
  --
  -- The link side is a layer-1 stream of nsl_inet.stream_mac, with an
  -- FCS unless l1_has_fcs_c is false.  As the tag changes the frame
  -- length, the FCS is checked and stripped on the way in and
  -- recomputed on the way out.  Frames failing the FCS check leave
  -- their pipe with the reject flag set.
  --
  -- By default, per-VID pipes carry the mac side stream, no FCS.  With
  -- routed_has_fcs_c, they are layer-1 streams too, so a layer-1
  -- interface can sit directly on a pipe: frames leaving through a
  -- pipe are padded to the minimum frame size (removing the tag can
  -- take them under it) and get an FCS, frames entering a pipe have
  -- their FCS checked and stripped, and a frame failing the check is
  -- cancelled before it reaches the link (it leaves with a corrupted
  -- FCS, see stream_mac_transmitter).
  --
  -- There is no buffering beyond the routing stages: a stalled pipe
  -- eventually stalls the link.
  component stream_vlan_path_router is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      vlan_id_c : vlan_id_vector;
      native_vlan_id_c : vlan_id_t := 0;
      l1_has_fcs_c : boolean := true;
      routed_has_fcs_c : boolean := false
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      rx_vlan_i : in master_t;
      rx_vlan_o : out slave_t;

      tx_vlan_o : out master_t;
      tx_vlan_i : in slave_t;

      rx_routed_o : out master_vector(0 to vlan_id_c'length-1);
      rx_routed_i : in slave_vector(0 to vlan_id_c'length-1);

      tx_routed_i : in master_vector(0 to vlan_id_c'length-1);
      tx_routed_o : out slave_vector(0 to vlan_id_c'length-1)
      );
  end component;

end package;

package body stream_vlan is

  function vlan_index(vlan_id: vlan_id_vector;
                      vid: vlan_id_t) return integer
  is
    alias v: vlan_id_vector(0 to vlan_id'length-1) is vlan_id;
  begin
    for i in v'range
    loop
      if v(i) = vid then
        return i;
      end if;
    end loop;

    return -1;
  end function;

end package body;
