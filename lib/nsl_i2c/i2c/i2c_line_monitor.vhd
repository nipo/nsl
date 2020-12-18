library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_i2c;

entity i2c_line_monitor is
  generic(
    debounce_count_c : integer
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;
    raw_i : in nsl_i2c.i2c.i2c_i;
    filtered_o : out nsl_i2c.i2c.i2c_i;
    start_o : out std_ulogic;
    stop_o : out std_ulogic
    );
end entity;

architecture beh of i2c_line_monitor is

  signal sda_rising, sda_falling : std_ulogic;
  signal scl_filtered: std_ulogic;

begin

  scl: nsl_clocking.async.async_input
    generic map(
      debounce_count_c => debounce_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => raw_i.scl,
      data_o => scl_filtered,
      rising_o => open,
      falling_o => open
      );

  sda: nsl_clocking.async.async_input
    generic map(
      debounce_count_c => debounce_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => raw_i.sda,
      data_o => filtered_o.sda,
      rising_o => sda_rising,
      falling_o => sda_falling
      );

  filtered_o.scl <= scl_filtered;
  start_o <= sda_falling and scl_filtered;
  stop_o <= sda_rising and scl_filtered;
  
end architecture;
