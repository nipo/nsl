library ieee;
use ieee.std_logic_1164.all;

entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
    );
end entity;

architecture gen of reset_at_startup is

  signal sh : std_ulogic_vector(0 to 8) := (others => '0');
  attribute keep : string;
  attribute keep of sh : signal is "TRUE";

begin

  reset_n_o <= sh(0);

  gen: process(clock_i)
  begin
    if rising_edge(clock_i) then
      sh <= sh(1 to 8) & '1';
    end if;
  end process;

end;
