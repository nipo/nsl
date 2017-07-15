library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_2p is
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
end ram_2p;

architecture syn of ram_2p is

  subtype word_t is std_ulogic_vector(data_size - 1 downto 0);
  type mem_t is array(2**addr_size - 1 downto 0) of word_t;
  shared variable r_mem: mem_t;

begin

  process (p_clk1)
  begin
    if rising_edge(p_clk1) then
      if p_wren1 = '1' then
        r_mem(to_integer(unsigned(p_addr1))) := p_wdata1;
      end if;

      p_rdata1 <= r_mem(to_integer(unsigned(p_addr1)));
    end if;
  end process;

  process (p_clk2)
  begin
    if rising_edge(p_clk2) then
      if p_wren2 = '1' then
        r_mem(to_integer(unsigned(p_addr2))) := p_wdata2;
      end if;

      if passthrough_12
        and p_addr1 = p_addr2
        and p_wren1 = '1' then
        p_rdata2 <= p_wdata1;
      else
        p_rdata2 <= r_mem(to_integer(unsigned(p_addr2)));
      end if;
    end if;
  end process;

  assert not passthrough_12 or p_clk1 = p_clk2
    report "Passthrough expects synchronous ports of RAM"
    severity failure;

end syn;
