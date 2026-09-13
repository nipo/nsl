library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;
use nsl_clocking.async.all;

entity async_debouncer is
  generic(
    clock_i_hz_c: natural;
    stable_us_c: natural := 10000;
    reset_value_c: std_ulogic := '0'
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    data_i: in std_ulogic;
    data_o: out std_ulogic
    );
end entity;

architecture beh of async_debouncer is

begin

  input: nsl_clocking.async.async_input
    generic map(
      debounce_count_c => debounce_cycle_count(clock_i_hz_c, stable_us_c),
      reset_value_c => reset_value_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => data_i,
      data_o => data_o,

      rising_o => open,
      falling_o => open
      );

end architecture;
