library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_1p is
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
end ram_1p;

architecture inferred of ram_1p is

  subtype word_t is std_ulogic_vector(data_size - 1 downto 0);
  type mem_t is array(2**addr_size - 1 downto 0) of word_t;
  shared variable r_mem: mem_t;

begin

  process (p_clk)
  begin
    if rising_edge(p_clk) then
      if p_wen = '1' then
        r_mem(to_integer(unsigned(p_addr))) := p_wdata;
      end if;
      p_rdata <= r_mem(to_integer(unsigned(p_addr)));
    end if;
  end process;

end inferred;
