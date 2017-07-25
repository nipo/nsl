library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sync is

  component sync_resetn
  generic(
    cycle_count : natural := 2
    );
    port (
      p_resetn      : in  std_ulogic;
      p_clk         : in  std_ulogic;
      p_resetn_sync : out std_ulogic
      );
  end component;

  component sync_reg is
    generic(
      cycle_count : natural := 2;
      data_width : integer
      );
    port(
      p_clk : in std_ulogic;
      p_in  : in std_ulogic_vector(data_width-1 downto 0);
      p_out : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

end package sync;
