library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

-- UBX protocol of the u-blox GNSS receivers: frames start with the
-- two sync characters, then class, id, a little-endian 16-bit
-- payload length, the payload, and the two-byte Fletcher checksum
-- computed over class through payload.
package ubx is

  constant ubx_sync1_c : byte := to_byte(16#b5#);
  constant ubx_sync2_c : byte := to_byte(16#62#);

  constant ubx_class_nav_c : byte := to_byte(16#01#);
  constant ubx_id_nav_timegps_c : byte := to_byte(16#20#);
  constant ubx_nav_timegps_length_c : natural := 16;

  -- NAV-TIMEGPS payload offsets, fields little endian: iTOW [ms of
  -- week, U4], fTOW [ns remainder, I4], week [I2], leapS [I1],
  -- valid [X1: bit 0 tow, bit 1 week, bit 2 leap], tAcc [ns, U4].
  constant ubx_timegps_off_itow_c : natural := 0;
  constant ubx_timegps_off_week_c : natural := 8;
  constant ubx_timegps_off_leap_c : natural := 10;
  constant ubx_timegps_off_valid_c : natural := 11;
  constant ubx_timegps_off_tacc_c : natural := 12;

  constant gps_week_seconds_c : natural := 604800;

  -- Consumes the receiver's serial byte stream and decodes
  -- NAV-TIMEGPS.  The framer hunts the sync characters, follows
  -- every frame whatever its class, and verifies the checksum, so
  -- interleaved messages or line noise only cost the frames they
  -- corrupt.
  --
  -- One strobe_o pulse per accepted NAV-TIMEGPS, the outputs
  -- settled and held until the next one: second_o is the absolute
  -- second of the navigation epoch the frame describes,
  -- week * 604800 + iTOW / 1000 + epoch_offset_c -- pass
  -- nsl_time.timestamp.gps_to_ptp_offset_c to get the PTP
  -- timescale.  Multi-cycle arithmetic delays the strobe by tens of
  -- cycles after the last frame byte, orders of magnitude ahead of
  -- the next second.  The valid flags and tAcc come straight from
  -- the frame, for the consumer to gate discipline on.
  component ubx_nav_timegps is
    generic(
      epoch_offset_c : natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      byte_i : in byte;
      valid_i : in std_ulogic;

      second_o : out unsigned(31 downto 0);
      leap_s_o : out signed(7 downto 0);
      tow_valid_o : out std_ulogic;
      week_valid_o : out std_ulogic;
      leap_valid_o : out std_ulogic;
      tacc_o : out unsigned(31 downto 0);
      strobe_o : out std_ulogic
      );
  end component;

end package;
