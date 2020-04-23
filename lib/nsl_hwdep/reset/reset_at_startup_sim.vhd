library ieee;
use ieee.std_logic_1164.all;

entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
    );
end entity;

architecture gen of reset_at_startup is

  signal ctr: integer range 0 to 4 := 4;

begin

  reset_n_o <= '1' when ctr = 0 else '0';

  gen: process(clock_i)
  begin
    if rising_edge(clock_i) then
      if ctr /= 0 then
        ctr <= ctr - 1;
      end if;
    end if;
  end process;

end;
