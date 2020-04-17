library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package driver is

  type time_vector is array(natural range <>) of time;
  
  component simulation_driver
    generic (
      clock_count : natural;
      reset_time : time;
      done_count : natural
      );
    port (
      clock_period : in time_vector(0 to clock_count);
      reset_n_o : out std_ulogic;
      clock_o   : out std_ulogic_vector(0 to clock_count);
      done_i : in std_ulogic_vector(0 to done_count-1)
      );
  end component;

end package driver;
