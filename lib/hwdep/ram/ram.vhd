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

      p_wren  : in  std_ulogic;
      p_wdata : in  std_ulogic_vector (data_size-1 downto 0);

      p_rdata : out std_ulogic_vector (data_size-1 downto 0)
      );
  end component;

  component ram_2p
    generic (
      addr_size : natural;
      data_size : natural;
      passthrough_12 : boolean := false
      );
    port (
      p_clk1   : in  std_ulogic;
      p_addr1  : in  std_ulogic_vector (addr_size-1 downto 0);
      p_wren1  : in  std_ulogic;
      p_wdata1 : in  std_ulogic_vector (data_size-1 downto 0);
      p_rdata1 : out std_ulogic_vector (data_size-1 downto 0);

      p_clk2   : in  std_ulogic;
      p_addr2  : in  std_ulogic_vector (addr_size-1 downto 0);
      p_wren2  : in  std_ulogic;
      p_wdata2 : in  std_ulogic_vector (data_size-1 downto 0);
      p_rdata2 : out std_ulogic_vector (data_size-1 downto 0)
      );
  end component;

end package ram;
