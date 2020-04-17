library ieee;
use ieee.std_logic_1164.all;

entity reset_at_startup is
  port(
    p_clk       : in std_ulogic;
    p_resetn    : out std_ulogic
    );
end entity;

architecture gen of reset_at_startup is

  signal ctr: integer range 0 to 4 := 4;

begin

  p_resetn <= '1' when ctr = 0 else '0';

  gen: process(p_clk)
  begin
    if rising_edge(p_clk) then
      if ctr /= 0 then
        ctr <= ctr - 1;
      end if;
    end if;
  end process;

end;
