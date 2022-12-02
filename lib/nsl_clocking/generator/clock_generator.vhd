library ieee;
use ieee.std_logic_1164.all;

library nsl_math, work;
use nsl_math.fixed.all;

entity clock_generator is
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    period_i : in ufixed;
    
    clock_o   : out std_ulogic
    );
end entity;

architecture beh of clock_generator is

  subtype half_period_t is ufixed(period_i'left-1 downto period_i'right-1);

  signal half_period_s : half_period_t;
  signal tick_s: std_ulogic;
  
begin

  half_period_s <= period_i;
  
  ticker: work.tick.tick_generator
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      period_i => half_period_s,
      tick_o => tick_s
      );
  
  osc: work.tick.tick_oscillator
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      tick_i => tick_s,
      osc_o => clock_o
      );
  
end architecture;
