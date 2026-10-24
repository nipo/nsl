library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_i2c;

-- Sipeed PMOD-DVP: a 24-pin FPC socket for an OV2640/OV5640-class
-- camera module, spread over two double Pmods, with the regulators
-- the sensor needs.  Nothing sits on the signals but pull-ups.
--
-- Control connector (J1):
--   pin 1: SDA     pin 5: SCL
--   pin 2: RESETB  pin 6: VSYNC
--   pin 3: PWDN    pin 7: HREF
--   pin 4: D7      pin 8: XCLK
--
-- Data connector (J2):
--   pin 1: D6      pin 5: D5
--   pin 2: PCLK    pin 6: D4
--   pin 3: D0      pin 7: D3
--   pin 4: D1      pin 8: D2
--
-- SCCB, RESETB and PWDN are pulled up on the board to the sensor's
-- 2.8 V supply, so they are only ever pulled low or let go.  With
-- nothing driving PWDN, the sensor stays powered down.
--
-- PCLK does not land on a clock-capable pin on every carrier board.
package pmod_dvp is

  component pmod_dvp_pads is
    generic(
      -- Distribution of the pixel clock, see
      -- nsl_clocking.distribution.clock_buffer.
      pclk_buffer_mode_c: string := "global"
      );
    port(
      control_io: inout nsl_digilent.pmod.pmod_double_t;
      data_io: inout nsl_digilent.pmod.pmod_double_t;

      -- Sensor master clock.  The sensor answers nothing on SCCB
      -- without it.
      xclk_i: in std_ulogic;

      i2c_i: in nsl_i2c.i2c.i2c_o;
      i2c_o: out nsl_i2c.i2c.i2c_i;

      sensor_reset_n_i: in std_ulogic;
      sensor_power_down_i: in std_ulogic;

      pclk_o: out std_ulogic;
      vsync_o: out std_ulogic;
      href_o: out std_ulogic;
      data_o: out std_ulogic_vector(7 downto 0)
      );
  end component;

end package pmod_dvp;
