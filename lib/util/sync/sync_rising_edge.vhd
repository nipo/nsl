library ieee;
use ieee.std_logic_1164.all;

entity sync_rising_edge is
  generic(
    cycle_count : natural := 2
    );
  port(
    p_in  : in  std_ulogic;
    p_clk : in  std_ulogic;
    p_out : out std_ulogic
    );

end sync_rising_edge;

architecture rtl of sync_rising_edge is

  signal r_resync : std_ulogic_vector(cycle_count-1 downto 0);
  attribute keep : boolean;
  attribute keep of r_resync : signal is true;

begin

  rst: process (p_clk, p_in)
  begin
    gen: for i in 0 to cycle_count - 2 loop
      if p_in = '0' then
        r_resync(i) <= '0';
      elsif rising_edge(p_clk) then
        r_resync(i) <= r_resync(i+1);
      end if;
    end loop;

    if p_in = '0' then
      r_resync(cycle_count-1) <= '0';
    elsif rising_edge(p_clk) then
      r_resync(cycle_count-1) <= p_in;
    end if;
  end process;

  p_out <= '0' when r_resync /= (r_resync'range => '1') else '1';
  
end rtl;
