library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package intradomain is

  -- Basic multi-cycle synchronous register pipeline.  Mostly suited
  -- for retiming.
  component intradomain_multi_reg is
    generic(
      cycle_count_c : natural range 1 to 40 := 1;
      data_width_c : integer
      );
    port(
      clock_i : in std_ulogic;
      data_i  : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o  : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

end package intradomain;
