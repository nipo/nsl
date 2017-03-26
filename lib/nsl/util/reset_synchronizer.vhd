library ieee;
use ieee.std_logic_1164.all;

entity reset_synchronizer is
  generic(
    cycle_count : natural := 2
    );
  port(
    p_resetn      : in  std_ulogic;
    p_clk         : in  std_ulogic;
    p_resetn_sync : out std_ulogic
    );

end reset_synchronizer;

architecture rtl of reset_synchronizer is


  signal s_reset : std_ulogic_vector(cycle_count-1 downto 0);
  signal r_reset : std_ulogic_vector(cycle_count-1 downto 0);

begin  -- rtl

  rst: process (p_clk, p_resetn)
  begin  -- process rst
    if p_resetn = '0' then
      r_reset <= (others => '0');
    elsif p_clk'event and p_clk = '1' then
      r_reset <= s_reset;
    end if;
  end process rst;

  s_reset <= '1' & r_reset(s_reset'high downto 1);

  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_resetn_sync <= r_reset(0) and p_resetn;
    end if;
  end process;
  
end rtl;
