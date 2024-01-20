library ieee;
use ieee.std_logic_1164.all;

entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
    );
end entity;

architecture gen of reset_at_startup is

  signal sh : std_ulogic_vector(0 to 7) := (others => '0');
  attribute keep : string;
  attribute keep of sh : signal is "TRUE";
  attribute syn_srlstyle:string;
  attribute syn_srlstyle of sh : signal is "registers";
  attribute syn_preserve:integer;
  attribute syn_preserve of sh : signal is 1;
  
begin

  gen: process(clock_i)
  begin
    if rising_edge(clock_i) then
      sh <= sh(1 to 7) & not sh(7);
      if sh = "01010101" or sh = "10101010" then
        reset_n_o <= '1';
      else
        reset_n_o <= '0';
      end if;
    end if;
  end process;

end;
