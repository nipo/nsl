library ieee;
use ieee.std_logic_1164.all;

entity sync_rising_edge is
  generic(
    cycle_count : natural := 2;
    async_reset : boolean := true
    );
  port(
    p_in  : in  std_ulogic;
    p_clk : in  std_ulogic;
    p_out : out std_ulogic
    );

end sync_rising_edge;

architecture rtl of sync_rising_edge is

  signal r_resync : std_ulogic_vector(0 to cycle_count-1);
  attribute keep : string;
  attribute keep of r_resync : signal is "TRUE";

begin

  rst: process (p_clk, p_in)
  begin
    if async_reset and p_in = '0' then
      r_resync <= (others => '0');
    elsif rising_edge(p_clk) then
      if not async_reset and p_in = '0' then
        r_resync <= (others => '0');
      else
        r_resync <= r_resync(1 to cycle_count - 1) & '1';
      end if;
    end if;
  end process;

  p_out <= '1' when r_resync = (r_resync'range => '1') else '0';
  
end rtl;
