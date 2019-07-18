library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

entity ram_2p_r_w is
  generic (
    addr_size : natural;
    data_size : natural;
    clk_count : natural range 1 to 2 := 1;
    bypass : boolean := false;
    registered_output : boolean := false
    );
  port (
    p_clk    : in  std_ulogic_vector(0 to clk_count-1);

    p_waddr  : in  std_ulogic_vector (addr_size-1 downto 0);
    p_wen    : in  std_ulogic := '0';
    p_wdata  : in  std_ulogic_vector (data_size-1 downto 0) := (others => '-');

    p_raddr  : in  std_ulogic_vector (addr_size-1 downto 0);
    p_ren  : in  std_ulogic := '0';
    p_rdata : out std_ulogic_vector (data_size-1 downto 0)
    );
end ram_2p_r_w;

architecture hier of ram_2p_r_w is

begin

  impl: hwdep.ram.ram_2p_homogeneous
    generic map(
      addr_size => addr_size,
      word_size => data_size,
      data_word_count => 1,
      registered_output => registered_output
      )
    port map(
      p_a_clk => p_clk(0),
      p_a_en => p_wen,
      p_a_wen(0) => p_wen,
      p_a_addr => p_waddr,
      p_a_wdata => p_wdata,
      p_a_rdata => open,

      p_b_clk => p_clk(clk_count-1),
      p_b_en => p_ren,
      p_b_wen(0) => '0',
      p_b_addr => p_raddr,
      p_b_wdata => (others => '-'),
      p_b_rdata => p_rdata
      );

end hier;
