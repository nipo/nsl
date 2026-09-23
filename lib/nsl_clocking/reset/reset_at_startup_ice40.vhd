library ieee;
use ieee.std_logic_1164.all;

entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
    );
end entity;

architecture ice of reset_at_startup is

  -- Lattice tools ignore initial values for registers.  They are
  -- always reset to 0.

  -- If we do not force-keep registers, constant is propagated by
  -- synplify and output is always '1'.
  
  signal sh : std_ulogic_vector(0 to 8) := (others => '0');
  attribute syn_keep : boolean;
  attribute syn_keep of sh : signal is true;

begin

  reset_n_o <= sh(0);

  gen: process(clock_i)
  begin
    if rising_edge(clock_i) then
      sh <= sh(1 to 8) & '1';
    end if;
  end process;

end;
