library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

-- OV5640 is a 5 megapixel CMOS image sensor with a DVP and a MIPI
-- CSI-2 output, configured over SCCB.
package ov5640 is

  constant i2c_saddr_default_c : unsigned(7 downto 1) := "0111100";

  -- Sensor setups.  All of them take the whole array width, binned
  -- 2x2.  Given PCLK figures are for a 24MHz XCLK.
  type mode_t is (
    -- 4:3 window, 640x480 after binning and scaling.  PCLK runs near
    -- 32MHz.
    MODE_VGA,
    -- 16:9 window, 1280x720 after binning, 15 frames a second.  PCLK
    -- runs at 42MHz, a line takes 3784 PCLK cycles, 2560 of them with
    -- HREF high.
    MODE_720P15,
    -- As MODE_720P15, 30 frames a second, PCLK runs at 84MHz.
    MODE_720P30
    );

  -- Powers the sensor up and sets it to stream RGB565 on its DVP
  -- port.
  --
  -- Sensor takes the window mode_c gives and scales it down to
  -- width_c x height_c, which may not be larger than the window.
  -- Pixels go out as two bytes, first one holding red and upper bits
  -- of green, data valid on PCLK rising edge, HREF and VSYNC active
  -- high.
  --
  -- XCLK has to run before reset is released.  Driver holds the
  -- sensor in power down and reset for a while, releases it, checks
  -- its identification, then writes its configuration.  If sensor
  -- does not answer, or answers with another identification, the
  -- whole sequence is retried after a second.
  --
  -- test_pattern_i replaces the picture by color bars.  It may change
  -- any time, it is applied once sensor is configured.
  component ov5640_driver is
    generic(
      clock_i_hz_c : natural;
      i2c_saddr_c : unsigned(7 downto 1) := i2c_saddr_default_c;
      mode_c : mode_t := MODE_VGA;
      width_c : positive range 1 to 1280 := 640;
      height_c : positive range 1 to 720 := 480
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Framed master port to a nsl_i2c.transactor.transactor_framed_controller.
      -- Every transaction sets the transactor SCL divisor to
      -- i2c_divisor_i, see nsl_i2c.transactor.scl_divisor.  The chip
      -- takes up to 400kHz.  Pseudo-constant.
      i2c_divisor_i : in unsigned(4 downto 0);
      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in nsl_bnoc.framed.framed_ack;
      rsp_i : in nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack;

      test_pattern_i : in std_ulogic := '0';

      -- Sensor RESETB and PWDN pins.  On modules where these have
      -- pull-ups to the sensor supply, drive them as open drain.
      sensor_reset_n_o : out std_ulogic;
      sensor_power_down_o : out std_ulogic;

      -- Sensor is configured and streaming.
      ready_o : out std_ulogic
      );
  end component;

end package;
