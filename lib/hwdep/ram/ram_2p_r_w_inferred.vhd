library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_2p_r_w is
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
    p_ren  : in  std_ulogic := '0';
    p_rdata : out std_ulogic_vector (data_size-1 downto 0)
    );
end ram_2p_r_w;

architecture inferred of ram_2p_r_w is

  subtype word_t is std_ulogic_vector(data_size - 1 downto 0);
  type mem_t is array(2**addr_size - 1 downto 0) of word_t;
  shared variable r_mem: mem_t;

begin
  
  process (p_clk(0), p_wen)
  begin
    if rising_edge(p_clk(0)) and p_wen = '1' then
      r_mem(to_integer(unsigned(p_waddr))) := p_wdata;
    end if;
  end process;

  process (p_clk(clk_count - 1), p_ren)
  begin
    if rising_edge(p_clk(clk_count - 1)) and p_ren = '1' then
      if clk_count = 1 and bypass and p_waddr = p_raddr and p_wen = '1' then
        p_rdata <= p_wdata;
      else
        p_rdata <= r_mem(to_integer(unsigned(p_raddr)));
      end if;
    end if;
  end process;

end inferred;
