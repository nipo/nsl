library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_math, nsl_amba;

-- Texas Instruments ADS8028: 8-channel 12-bit SPI ADC with an internal
-- temperature sensor.
package ads8028 is

  -- Channels of the device: AIN0 to AIN7, then the temperature sensor.
  constant channel_count_c : natural := 9;
  constant temperature_c : natural := 8;

  subtype channel_mask_t is std_ulogic_vector(0 to channel_count_c-1);
  constant all_channels_c : channel_mask_t := (others => '1');

  -- Conversion result, straight binary of the fraction of the reference
  -- for AINx, twos complement quarters of degree Celsius for the
  -- temperature sensor.
  subtype code_t is unsigned(11 downto 0);
  type code_vector is array(natural range <>) of code_t;

  -- Fraction of the reference voltage of an AINx code.
  function to_ratio(code : code_t) return nsl_math.fixed.ufixed;
  -- Temperature of a temperature sensor code, in degrees Celsius.
  function to_celsius(code : code_t) return nsl_math.fixed.sfixed;

  -- Continuously scans the enabled channels of an ADS8028 through an
  -- nsl_spi framed transactor, possibly shared with other devices.
  --
  -- The device runs in repeat mode, each frame is a self-contained
  -- framed transactor command (clock divisor, select, 16-bit shift,
  -- unselect). Results carry the address of their channel, they are
  -- stored by address, so the scanner never loses track of the
  -- sequence. The control register is written after reset, and again
  -- when resync_frames_c frames in a row bring no result of an enabled
  -- channel, e.g. after a reset or a power cycle of the device.
  --
  -- While the temperature sensor converts (up to 100 us), the device
  -- answers all ones. With busy_i connected to TM_BUSY, the scanner
  -- waits for its end instead.
  component ads8028_framed_scanner is
    generic(
      -- Channels converted
      channels_c : channel_mask_t := all_channels_c;
      -- Reference from the REF pin instead of the internal one
      external_reference_c : boolean := false;
      -- Rolling average of the temperature sensor
      temperature_averaging_c : boolean := false;
      -- Chip select of the device on the transactor
      slave_no_c : natural range 0 to 6;
      -- SCK = clock_i / (2 * divisor_c), 20 MHz max
      divisor_c : natural range 1 to 128;
      -- Clock cycles between the end of a frame and the start of the
      -- next one, sets the sampling rate
      frame_gap_c : natural := 0;
      -- Frames without a result before the control register is
      -- written again
      resync_frames_c : positive := 256
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in  nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack;

      -- TM_BUSY pin, asynchronous
      busy_i : in std_ulogic := '0';

      -- Last result of each channel
      code_o : out code_vector(0 to channel_count_c-1);
      -- A result was received since reset
      valid_o : out channel_mask_t;
      -- Asserted for a cycle when a result is stored
      strobe_o : out channel_mask_t
      );
  end component;

  -- Read-only registers of the results of a scanner, on a 32-bit APB,
  -- 16 registers, little endian:
  --
  -- * 0 to 8, channel results: bit 31 set once the channel has a
  --   result, bits 23-16 count results, wrapping, bits 11-0 hold the
  --   last code,
  -- * 15, INFO: bits 31-16 register layout version, 1, bits 8-0
  --   channels the scanner converts.
  --
  -- Other registers read 0, writes are ignored.
  component ads8028_apb_registers is
    generic(
      config_c : nsl_amba.apb.config_t;
      channels_c : channel_mask_t := all_channels_c
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      apb_i : in nsl_amba.apb.master_t;
      apb_o : out nsl_amba.apb.slave_t;

      code_i : in code_vector(0 to channel_count_c-1);
      valid_i : in channel_mask_t;
      strobe_i : in channel_mask_t
      );
  end component;

end package;

package body ads8028 is

  function to_ratio(code : code_t) return nsl_math.fixed.ufixed
  is
    variable ret : nsl_math.fixed.ufixed(-1 downto -12);
  begin
    ret := nsl_math.fixed.ufixed(code);
    return ret;
  end function;

  function to_celsius(code : code_t) return nsl_math.fixed.sfixed
  is
    variable ret : nsl_math.fixed.sfixed(9 downto -2);
  begin
    ret := nsl_math.fixed.sfixed(code);
    return ret;
  end function;

end package body;
