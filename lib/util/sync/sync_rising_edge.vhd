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

  signal r_resync : std_ulogic_vector(0 to cycle_count-1);
  attribute keep : boolean;
  attribute keep of r_resync : signal is true;
  attribute async_reg : string;
  attribute async_reg of r_resync : signal is "true";

begin

  rst: process (p_clk, p_in)
  begin
    if p_in = '0' then
      r_resync <= (others => '0');
    elsif rising_edge(p_clk) then
      r_resync <= r_resync(r_resync'left + 1 to r_resync'right) & '1';
    end if;
  end process;

  p_out <= r_resync(0);
  
end rtl;
