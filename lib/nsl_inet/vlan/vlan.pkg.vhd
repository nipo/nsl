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
-- The demux inspects the ethertype: frames carrying the 802.1Q TPID
-- have TPID and TCI consumed and are routed on VID, one pipe per
-- configured VID; other frames are forwarded untouched to the
-- untagged pipe.  The mux does the reverse, inserting TPID and TCI
-- on frames coming from a VID pipe.
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
  -- tagged_o pipe.  Frames with no 802.1Q TPID are forwarded
  -- untouched to the untagged pipe.  Tagged frames with an
  -- unconfigured VID are dropped.
  component vlan_demux is
    generic(
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0;
      vlan_id_c : vlan_id_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_bnoc.committed.committed_req;
      in_o : out nsl_bnoc.committed.committed_ack;

      untagged_o : out nsl_bnoc.committed.committed_req;
      untagged_i : in nsl_bnoc.committed.committed_ack;

      tagged_o : out nsl_bnoc.committed.committed_req_array(0 to vlan_id_c'length-1);
      tagged_i : in nsl_bnoc.committed.committed_ack_array(0 to vlan_id_c'length-1)
      );
  end component;

  -- Merges per-VID pipes and an untagged pipe to a single MAC
  -- boundary stream.  Frames from a tagged_i pipe get TPID and TCI
  -- inserted after the source address, with the VID matching the
  -- pipe.  Frames from the untagged pipe are forwarded untouched.
  component vlan_mux is
    generic(
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0;
      vlan_id_c : vlan_id_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      untagged_i : in nsl_bnoc.committed.committed_req;
      untagged_o : out nsl_bnoc.committed.committed_ack;

      tagged_i : in nsl_bnoc.committed.committed_req_array(0 to vlan_id_c'length-1);
      tagged_o : out nsl_bnoc.committed.committed_ack_array(0 to vlan_id_c'length-1);

      out_o : out nsl_bnoc.committed.committed_req;
      out_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

end package;
