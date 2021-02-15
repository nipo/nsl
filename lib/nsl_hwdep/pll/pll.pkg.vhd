library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pll is

  component pll_basic
    generic(
      input_hz_c  : natural;
      output_hz_c : natural;
      hw_variant_c : string := ""
      );
    port(
      clock_i    : in  std_ulogic;
      clock_o    : out std_ulogic;

      reset_n_i  : in  std_ulogic;
      locked_o   : out std_ulogic
      );
  end component;

end package pll;
