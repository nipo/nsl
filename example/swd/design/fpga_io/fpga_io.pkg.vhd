library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fpga_io is
  component swd_main is
    generic(
      rom_base : unsigned(31 downto 0) := x"00000000";
      dp_idr : unsigned(31 downto 0) := X"0ba00477"; 
      ap_idr : unsigned(31 downto 0) := X"04770004"
      );
    port (
      led: out std_logic;
      swclk : in std_logic;
      swdio : inout std_logic
      );
  end component;
end package;
