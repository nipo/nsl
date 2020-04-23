library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package driver is

  type time_vector is array(natural range <>) of time;
  
  component simulation_driver
    generic (
      clock_count : natural;
      reset_count : natural;
      done_count : natural
      );
    port (
      clock_period : in time_vector(0 to clock_count-1);
      reset_duration : in time_vector(0 to reset_count-1);
      reset_n_o : out std_ulogic_vector(0 to reset_count-1);
      clock_o   : out std_ulogic_vector(0 to clock_count-1);
      done_i : in std_ulogic_vector(0 to done_count-1)
      );
  end component;

end package driver;
