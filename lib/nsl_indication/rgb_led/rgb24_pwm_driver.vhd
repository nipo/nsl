library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_math, nsl_signal_generator;

entity rgb24_pwm_driver is
  generic (
    clock_prescaler_c : positive := 1;
    active_value_c : std_ulogic := '1'
    );
  port (
    reset_n_i     : in  std_ulogic;
    clock_i       : in  std_ulogic;

    color_i       : in nsl_color.rgb.rgb24;
    led_o         : out nsl_color.rgb.rgb3
    );
end entity;

architecture beh of rgb24_pwm_driver is

  signal a_r, a_g, a_b, i_r, i_g, i_b : unsigned(7 downto 0);
  constant mag : positive := nsl_math.arith.log2(clock_prescaler_c);
  constant prescaler_c : unsigned(mag-1 downto 0) := to_unsigned(clock_prescaler_c, mag);

begin

  a_r <= color_i.r;
  a_g <= color_i.g;
  a_b <= color_i.b;
  i_r <= not a_r;
  i_g <= not a_g;
  i_b <= not a_b;

  r_pwm: nsl_signal_generator.pwm.pwm_generator
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      pwm_o => led_o.r,

      prescaler_i => prescaler_c,

      active_duration_i => a_r,
      inactive_duration_i => i_r,

      sync_o => open,
      active_value_i => active_value_c
      );

  g_pwm: nsl_signal_generator.pwm.pwm_generator
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      pwm_o => led_o.g,

      prescaler_i => prescaler_c,

      active_duration_i => a_g,
      inactive_duration_i => i_g,

      sync_o => open,
      active_value_i => active_value_c
      );

  b_pwm: nsl_signal_generator.pwm.pwm_generator
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      pwm_o => led_o.b,

      prescaler_i => prescaler_c,

      active_duration_i => a_b,
      inactive_duration_i => i_b,

      sync_o => open,
      active_value_i => active_value_c
      );

end architecture beh;
