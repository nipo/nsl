library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_inet, nsl_time;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.mac.all;
use nsl_time.timestamp.all;

-- IEEE 1588-2019 (PTP) message definitions shared by the transport
-- flavors.
package ptp is

  constant ptp_ethertype_c : natural := 16#88F7#;

  -- Forwardable default-domain address, end-to-end delay mechanism.
  constant ptp_multicast_addr_c : mac48_t := from_hex("011b19000000");
  -- Non-forwardable address, peer delay and gPTP.
  constant ptp_multicast_pdelay_addr_c : mac48_t := from_hex("0180c200000e");

  constant ptp_msg_sync_c : natural := 0;
  constant ptp_msg_delay_req_c : natural := 1;
  constant ptp_msg_follow_up_c : natural := 8;
  constant ptp_msg_delay_resp_c : natural := 9;
  constant ptp_msg_announce_c : natural := 11;

  -- Common header field offsets, RFC-style from message start.
  constant ptp_off_type_c : natural := 0;
  constant ptp_off_version_c : natural := 1;
  constant ptp_off_length_c : natural := 2;
  constant ptp_off_domain_c : natural := 4;
  constant ptp_off_flags_c : natural := 6;
  constant ptp_off_correction_c : natural := 8;
  constant ptp_off_source_port_identity_c : natural := 20;
  constant ptp_off_sequence_id_c : natural := 30;
  constant ptp_off_control_c : natural := 32;
  constant ptp_off_log_interval_c : natural := 33;
  -- First body field of every message handled here: origin, precise
  -- origin or receive timestamp.
  constant ptp_off_timestamp_c : natural := 34;
  -- Delay_Resp only.
  constant ptp_off_requesting_port_identity_c : natural := 44;

  -- Announce body, after the (zero) origin timestamp.
  constant ptp_off_utc_offset_c : natural := 44;
  constant ptp_off_gm_priority1_c : natural := 47;
  -- clockClass, clockAccuracy, then offsetScaledLogVariance.
  constant ptp_off_gm_quality_c : natural := 48;
  constant ptp_off_gm_priority2_c : natural := 52;
  constant ptp_off_gm_identity_c : natural := 53;
  constant ptp_off_steps_removed_c : natural := 61;
  constant ptp_off_time_source_c : natural := 63;

  constant ptp_clock_class_locked_c : natural := 6;
  constant ptp_clock_class_holdover_c : natural := 7;
  constant ptp_clock_class_default_c : natural := 248;

  constant ptp_time_source_gps_c : byte := to_byte(16#20#);
  constant ptp_time_source_internal_c : byte := to_byte(16#a0#);

  constant ptp_sync_length_c : natural := 44;
  constant ptp_announce_length_c : natural := 64;
  constant ptp_delay_req_length_c : natural := 44;
  constant ptp_follow_up_length_c : natural := 44;
  constant ptp_delay_resp_length_c : natural := 54;

  -- twoStepFlag, in the first flag byte.
  constant ptp_flag0_two_step_c : natural := 1;
  -- Time properties, in the second flag byte, meaningful in Announce.
  constant ptp_flag1_leap61_c : natural := 0;
  constant ptp_flag1_leap59_c : natural := 1;
  constant ptp_flag1_utc_offset_valid_c : natural := 2;
  constant ptp_flag1_ptp_timescale_c : natural := 3;
  constant ptp_flag1_time_traceable_c : natural := 4;
  constant ptp_flag1_frequency_traceable_c : natural := 5;

  -- TAI runs this many seconds ahead of GPS time, so a receiver's
  -- GPS-UTC leap second count plus this is currentUtcOffset.
  constant ptp_tai_minus_gps_c : natural := 19;

  -- clockIdentity [8] then portNumber [2], big endian.
  subtype ptp_port_identity_t is byte_string(0 to 9);

  -- On-wire timestamp: 48-bit seconds then 32-bit nanoseconds, big
  -- endian.  The local 32-bit second span maps to the low half of
  -- the second field, high bytes zero on emission, ignored on
  -- reception.
  subtype ptp_timestamp_bytes_t is byte_string(0 to 9);

  function to_ptp_timestamp(ts: timestamp_t) return ptp_timestamp_bytes_t;
  function from_ptp_timestamp(data: byte_string) return timestamp_t;

end package;

package body ptp is

  function to_ptp_timestamp(ts: timestamp_t) return ptp_timestamp_bytes_t
  is
    variable ret: ptp_timestamp_bytes_t := (others => x"00");
  begin
    ret(2 to 5) := to_be(ts.second);
    ret(6 to 9) := to_be(resize(ts.nanosecond, 32));
    return ret;
  end function;

  function from_ptp_timestamp(data: byte_string) return timestamp_t
  is
    alias xd: byte_string(0 to 9) is data;
    variable ret: timestamp_t := timestamp_zero_c;
  begin
    assert data'length = 10
      report "Bad PTP timestamp length"
      severity failure;

    ret.second := from_be(xd(2 to 5));
    ret.nanosecond := resize(from_be(xd(6 to 9)), 30);
    return ret;
  end function;

end package body;
