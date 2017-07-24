library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package ram is

  component ram_1p
    generic (
      addr_size : natural;
      data_size : natural
      );
    port (
      p_clk   : in  std_ulogic;

      p_addr  : in  std_ulogic_vector (addr_size-1 downto 0);

      p_wen   : in  std_ulogic;
      p_wdata : in  std_ulogic_vector (data_size-1 downto 0);

      p_rdata : out std_ulogic_vector (data_size-1 downto 0)
      );
  end component;

  component ram_2p_r_w
    generic (
      addr_size : natural;
      data_size : natural;
      clk_count : natural range 1 to 2 := 1;
      bypass : boolean := false
      );
    port (
      p_clk    : in  std_ulogic_vector(0 to clk_count-1);

      p_waddr  : in  std_ulogic_vector (addr_size-1 downto 0);
      p_wen    : in  std_ulogic := '0';
      p_wdata  : in  std_ulogic_vector (data_size-1 downto 0) := (others => '-');

      p_raddr  : in  std_ulogic_vector (addr_size-1 downto 0);
      p_ren    : in  std_ulogic := '1';
      p_rdata  : out std_ulogic_vector (data_size-1 downto 0)
      );
  end component;

end package ram;
