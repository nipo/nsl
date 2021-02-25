library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package config is

  component config_series7 is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      run_i : in std_ulogic;
      next_address_i : in unsigned(28 downto 0);
      rs_i : in std_ulogic_vector(1 downto 0) := "00";
      rs_en_i : in std_ulogic := '0'
      );
  end component;

end package;

      
