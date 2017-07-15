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

  signal r_reset : std_ulogic_vector(cycle_count-1 downto 0);
  attribute keep : boolean;
  attribute keep of r_reset : signal is true;

begin  -- rtl

  rst: process (p_clk, p_resetn)
  begin
    gen: for i in 0 to cycle_count - 2 loop
      if p_resetn = '0' then
        r_reset(i) <= '0';
      elsif rising_edge(p_clk) then
        r_reset(i) <= r_reset(i+1);
      end if;
    end loop;

    if p_resetn = '0' then
      r_reset(cycle_count-1) <= '0';
    elsif rising_edge(p_clk) then
      r_reset(cycle_count-1) <= p_resetn;
    end if;
  end process;

  p_resetn_sync <= '0' when r_reset /= (r_reset'range => '1') else '1';
  
end rtl;
