library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, work;
use nsl_bnoc.committed.all;
use work.mac.all;

-- 802.1Q VLAN tagging.  Operates on the transparent MAC boundary
-- (nsl_inet.mac): frames enter and leave every pipe as
--
-- * Optional pre-header [N]
-- * Destination MAC [6]
-- * Source MAC [6]
-- * Ethertype [2]
-- * Payload [*]
-- * Status byte
--   [0]   Whether frame is valid
--   [7:1] Reserved
--
-- There is one pipe per configured VID.  Untagged frames belong to
-- the native VLAN: on the demux they are merged, tag-less, into the
-- pipe whose VID matches native_vlan_id_c; on the mux, frames from
-- that pipe are sent without a 802.1Q header.  If native_vlan_id_c
-- is not part of vlan_id_c, untagged frames are dropped like any
-- unconfigured VID.  As VID 0 is reserved by 802.1Q, the default
-- native VLAN drops untagged frames.
--
-- As every pipe speaks the mac boundary format, per-VID branches may
-- be stacked with nsl_inet.ethernet host adaptation, another vlan
-- demux (802.1ad style), or wired to another mac transmitter to
-- build a transparent fan-out device.
--
-- Priority tagging is not supported: PCP and DEI are discarded on
-- receive and transmitted as zero.
package vlan is

  subtype vlan_id_t is integer range 0 to 4095;
  type vlan_id_vector is array(integer range <>) of vlan_id_t;

  -- Routes frames on their 802.1Q tag.  Tagged frames matching a
  -- configured VID have TPID and TCI consumed and go to the matching
  -- vlan_o pipe.  Untagged frames go, untouched, to the pipe
  -- matching native_vlan_id_c.  Other frames are dropped.
  component vlan_demux is
    generic(
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0;
      vlan_id_c : vlan_id_vector;
      native_vlan_id_c : vlan_id_t := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_bnoc.committed.committed_req;
      in_o : out nsl_bnoc.committed.committed_ack;

      vlan_o : out nsl_bnoc.committed.committed_req_array(0 to vlan_id_c'length-1);
      vlan_i : in nsl_bnoc.committed.committed_ack_array(0 to vlan_id_c'length-1)
      );
  end component;

  -- Merges per-VID pipes to a single MAC boundary stream.  Frames
  -- get TPID and TCI inserted after the source address, with the VID
  -- matching the pipe, except for the pipe matching
  -- native_vlan_id_c, whose frames are forwarded untouched.
  component vlan_mux is
    generic(
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0;
      vlan_id_c : vlan_id_vector;
      native_vlan_id_c : vlan_id_t := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      vlan_i : in nsl_bnoc.committed.committed_req_array(0 to vlan_id_c'length-1);
      vlan_o : out nsl_bnoc.committed.committed_ack_array(0 to vlan_id_c'length-1);

      out_o : out nsl_bnoc.committed.committed_req;
      out_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

end package;
