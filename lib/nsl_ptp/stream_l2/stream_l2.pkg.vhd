library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_mii, nsl_time, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_mii.timestamping.all;
use nsl_time.timestamp.all;

-- PTP over ethernet (IEEE 1588-2019 annex E), ordinary clocks on the
-- AXI4-Stream protocol suite.  An engine owns a 0x88F7 ethertype
-- pipe pair of the ethernet layer and speaks the end-to-end delay
-- mechanism, two-step; the slave also accepts one-step Syncs.
--
-- Packets on the pipes carry the header_length_c blocks, then the
-- PTP message; the FIRST block must be the timestamping tag of
-- nsl_mii.timestamping.  On receive the engine claims the capture
-- register the tag designates through the capture_id_o /
-- capture_time_i read port the moment the tag byte enters, giving
-- the frame's SFD time.  On transmit the engine fills the tag
-- itself, requesting the strobe on its event messages, and latches
-- timestamp_i when tx_strobe_i fires; only the engine's event
-- messages request strobes, so no identifier bookkeeping is needed
-- beyond one outstanding event frame, which the protocol
-- guarantees.
--
-- The layer-2 context of transmitted messages carries multicast
-- casting group multicast_group_c; the ethernet transmitter's
-- multicast table is expected to hold ptp_multicast_addr_c at that
-- index, and the receiver to accept it.
--
-- Announce and the best master clock algorithm are not implemented:
-- the slave locks on the first master it hears a Sync from and
-- ignores others until sync_timeout_c seconds without a Sync unlock
-- it.  Engines are byte-wide only.
package stream_l2 is

  -- Slave ordinary clock.  Collects T1/T2 from Sync (and Follow_Up
  -- when two-step, correction fields folded in), T3/T4 from a
  -- Delay_Req exchange every delay_req_period_c seconds, and streams
  -- discipline measurements: offset_o qualified by offset_valid_o is
  -- local time minus master time (nsl_time.discipline currency).
  -- When the offset magnitude exceeds step_threshold_ns_c or
  -- overflows the offset range, step_o qualified by step_valid_o
  -- requests an absolute clock set to the estimated master time
  -- instead.  path_delay_o holds the last mean path delay.
  -- locked_o reports a master is being tracked.
  component ptp_l2_slave is
    generic(
      config_c : config_t;
      header_length_c : integer_vector;
      clock_i_hz_c : natural;
      domain_c : natural := 0;
      delay_req_period_c : natural := 1;
      sync_timeout_c : natural := 8;
      step_threshold_ns_c : natural := 100000000;
      multicast_group_c : natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      clock_identity_i : in byte_string(0 to 7);

      timestamp_i : in timestamp_t;

      capture_id_o : out tag_id_t;
      capture_time_i : in timestamp_t;

      tx_strobe_i : in std_ulogic;
      tx_id_i : in tag_id_t;

      rx_i : in master_t;
      rx_o : out slave_t;
      tx_o : out master_t;
      tx_i : in slave_t;

      offset_o : out timestamp_nanosecond_offset_t;
      offset_valid_o : out std_ulogic;
      step_o : out timestamp_t;
      step_valid_o : out std_ulogic;
      path_delay_o : out timestamp_nanosecond_offset_t;
      locked_o : out std_ulogic
      );
  end component;

  -- Master ordinary clock, static: emits a two-step Sync every
  -- sync_period_c seconds with the strobe-requesting tag, latches
  -- timestamp_i at the strobe and follows up with the precise origin
  -- timestamp; answers every Delay_Req with a Delay_Resp carrying
  -- the requester's receive time from the capture file and its port
  -- identity.
  component ptp_l2_master is
    generic(
      config_c : config_t;
      header_length_c : integer_vector;
      clock_i_hz_c : natural;
      domain_c : natural := 0;
      sync_period_c : natural := 1;
      multicast_group_c : natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      clock_identity_i : in byte_string(0 to 7);

      timestamp_i : in timestamp_t;

      capture_id_o : out tag_id_t;
      capture_time_i : in timestamp_t;

      tx_strobe_i : in std_ulogic;
      tx_id_i : in tag_id_t;

      rx_i : in master_t;
      rx_o : out slave_t;
      tx_o : out master_t;
      tx_i : in slave_t
      );
  end component;

end package;
