library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sync is

  component sync_multi_resetn
    generic(
      cycle_count : natural := 2;
      clk_count : natural
      );
    port (
      p_clk : in  std_ulogic_vector(0 to clk_count-1);
      p_resetn  : in  std_ulogic;
      p_resetn_sync : out std_ulogic_vector(0 to clk_count-1)
      );
  end component;

  component sync_rising_edge
    generic(
      cycle_count : natural := 2
      );
    port (
      p_clk : in  std_ulogic;
      p_in  : in  std_ulogic;
      p_out : out std_ulogic
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

  component sync_cross_counter is
    generic(
      cycle_count : natural := 2;
      data_width : integer
      );
    port(
      p_in_clk : in std_ulogic;
      p_out_clk : in std_ulogic;
      p_in  : in unsigned(data_width-1 downto 0);
      p_out : out unsigned(data_width-1 downto 0)
      );
  end component;

end package sync;
