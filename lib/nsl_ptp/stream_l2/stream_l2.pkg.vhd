library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_mii, nsl_time, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_mii.timestamping.all;
use nsl_time.timestamp.all;
use work.ptp.all;

-- PTP over ethernet (IEEE 1588-2019 annex E), ordinary clocks on the
-- AXI4-Stream protocol suite.  An engine owns a 0x88F7 ethertype
-- pipe pair of the ethernet layer and speaks the end-to-end delay
-- mechanism, two-step; the slave also accepts one-step Syncs.
--
-- Packets on the pipes carry the header_length_c blocks, then the
-- PTP message; the FIRST block must be the timestamping tag of
-- nsl_mii.timestamping.  The engines never observe the time base:
-- every timestamp reaches them as a captured value, so the clock
-- may live in any domain.
--
-- On receive the engine claims the capture register the tag
-- designates through the capture_id_o / capture_time_i read port
-- the moment the tag byte enters, giving the frame's SFD time.  On
-- transmit the engine fills the tag itself with ptp_tx_tag_id_c,
-- requesting the strobe on its event messages; tx_strobe_i must
-- pulse once that event's capture register is written (the a_done_o
-- of the transmit timestamping_sideband_resync), and the engine
-- then claims tx_capture_time_i, the transmit capture file read at
-- ptp_tx_tag_id_c.  Only the engine's event messages request
-- strobes, and one is outstanding at a time, which the protocol
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

  -- Identifier the engines put in the tag of their event messages:
  -- the transmit capture file is read at this identifier.
  constant ptp_tx_tag_id_c : tag_id_t := (others => '0');

  -- Slave ordinary clock.  Collects T1/T2 from Sync (and Follow_Up
  -- when two-step, correction fields folded in), T3/T4 from a
  -- Delay_Req exchange every delay_req_period_c seconds, and streams
  -- discipline measurements: offset_o qualified by offset_valid_o is
  -- local time minus master time (nsl_time.discipline currency).
  -- When the offset magnitude exceeds step_threshold_ns_c or
  -- overflows the offset range, a step is requested instead:
  -- step_o, qualified by step_valid_o, is the master time of the
  -- Sync's departure plus the path delay, and step_sync_o the local
  -- capture time of its arrival; hand both to
  -- nsl_time.discipline.discipline_step_applier, which adds the
  -- local time elapsed since.  path_delay_o holds the last mean
  -- path delay.  locked_o reports a master is being tracked.
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

      capture_id_o : out tag_id_t;
      capture_time_i : in timestamp_t;

      tx_strobe_i : in std_ulogic;
      tx_capture_time_i : in timestamp_t;

      rx_i : in master_t;
      rx_o : out slave_t;
      tx_o : out master_t;
      tx_i : in slave_t;

      offset_o : out timestamp_nanosecond_offset_t;
      offset_valid_o : out std_ulogic;
      step_o : out timestamp_t;
      step_sync_o : out timestamp_t;
      step_valid_o : out std_ulogic;
      path_delay_o : out timestamp_nanosecond_offset_t;
      locked_o : out std_ulogic
      );
  end component;

  -- Master ordinary clock, static: emits a two-step Sync every
  -- sync_period_c seconds with the strobe-requesting tag, claims
  -- its departure time from the transmit capture file once
  -- tx_strobe_i reports it written, and follows up with the precise
  -- origin timestamp; answers every Delay_Req with a Delay_Resp
  -- carrying the requester's receive time from the capture file and
  -- its port identity.
  --
  -- With announce_c, an Announce goes out every announce_period_c
  -- seconds, behind everything else in the send order: third-party
  -- slaves will not adopt a master without it, while the sibling
  -- slave engine ignores it.  The grandmaster identity is
  -- clock_identity_i, priorities come from the generics, steps
  -- removed is zero, accuracy and variance are sent unknown, and
  -- the origin timestamp is zero.  clock_class_i and time_source_i
  -- follow the state of the time source: a GPS-disciplined
  -- grandmaster advertises ptp_clock_class_locked_c and
  -- ptp_time_source_gps_c while locked, holdover values otherwise,
  -- sampled at each emission.
  component ptp_l2_master is
    generic(
      config_c : config_t;
      header_length_c : integer_vector;
      clock_i_hz_c : natural;
      domain_c : natural := 0;
      sync_period_c : natural := 1;
      announce_c : boolean := false;
      announce_period_c : natural := 2;
      priority1_c : natural := 128;
      priority2_c : natural := 128;
      multicast_group_c : natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      clock_identity_i : in byte_string(0 to 7);
      clock_class_i : in unsigned(7 downto 0)
        := to_unsigned(ptp_clock_class_default_c, 8);
      time_source_i : in byte := ptp_time_source_internal_c;

      capture_id_o : out tag_id_t;
      capture_time_i : in timestamp_t;

      tx_strobe_i : in std_ulogic;
      tx_capture_time_i : in timestamp_t;

      rx_i : in master_t;
      rx_o : out slave_t;
      tx_o : out master_t;
      tx_i : in slave_t
      );
  end component;

end package;
