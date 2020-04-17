library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity intradomain_multi_reg is
  generic(
    cycle_count_c : natural range 1 to 40 := 2;
    data_width_c : integer
    );
  port(
    clock_i    : in std_ulogic;
    data_i     : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o    : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end intradomain_multi_reg;

architecture rtl of intradomain_multi_reg is
  
  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  signal r_regs : word_vector_t (0 to cycle_count_c-1);

begin

  clock: process (clock_i)
  begin
    if rising_edge(clock_i) then
      r_regs(r_regs'left to r_regs'right-1) <= r_regs(r_regs'left+1 to r_regs'right);
      r_regs(r_regs'right) <= data_i;
    end if;
  end process clock;

  data_o <= r_regs(r_regs'left);
  
end rtl;
