library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_data;
use nsl_data.prbs.all;

entity probability_stream_constant is
  generic (
    state_width_c: integer range 1 to 31 := 8;
    probability_c: real
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ready_i : in std_ulogic := '1';
    value_o : out std_ulogic
    );
end entity;

architecture beh of probability_stream_constant is

begin

  impl: work.probability.probability_stream
    generic map(
      state_width_c => state_width_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      probability_i => nsl_math.fixed.to_ufixed(probability_c, -1, -state_width_c),
      ready_i => ready_i,
      value_o => value_o
      );
  
end architecture;
