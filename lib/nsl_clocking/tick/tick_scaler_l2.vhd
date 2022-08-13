library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library nsl_math, nsl_dsp;
use nsl_math.fixed.all;

entity tick_scaler_l2 is
  generic(
    input_period_max_c: real;
    input_resolution_c: real;
    period_scale_l2_c: natural;
    tau_c : natural
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;
    tick_o : out std_ulogic
    );
end tick_scaler_l2;

architecture rtl of tick_scaler_l2 is

  constant measure_msb: integer := nsl_math.arith.max(0, integer(log2(input_period_max_c + 1.0)));
  constant measure_lsb: integer := nsl_math.arith.max(0, integer(log2(input_resolution_c)));

  signal measured_period_s : ufixed(measure_msb downto measure_lsb);
  signal generator_period_s : ufixed(measure_msb-period_scale_l2_c downto measure_lsb-period_scale_l2_c);
  
begin

  generator_period_s <= measured_period_s;
  
  measurer: work.tick.tick_measurer
    generic map(
      tau_c => tau_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      tick_i => tick_i,
      period_o => measured_period_s
      );

  generator: work.tick.tick_generator
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      period_i => generator_period_s,
      tick_o => tick_o
      );
  
end rtl;
