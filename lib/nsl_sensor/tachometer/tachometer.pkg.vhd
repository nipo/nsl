library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tachometer is

  component tick_tachometer is
    generic (
      clock_i_hz_c: real;
      update_rate_hz_c: real
      );
    port (
      reset_n_i     : in  std_ulogic;
      clock_i       : in  std_ulogic;

      tick_i : in std_ulogic;
      tick_per_period_o : out unsigned
      );
  end component;
  
end package tachometer;
