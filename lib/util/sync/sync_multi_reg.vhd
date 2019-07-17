library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_multi_reg is
  generic(
    cycle_count : natural range 1 to 40 := 2;
    data_width : integer
    );
  port(
    p_clk    : in std_ulogic;
    p_in     : in std_ulogic_vector(data_width-1 downto 0);
    p_out    : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_multi_reg;

architecture rtl of sync_multi_reg is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  signal r_regs : word_vector_t (0 to cycle_count-1);

begin

  clock: process (p_clk)
  begin
    if rising_edge(p_clk) then
      r_regs(r_regs'left to r_regs'right-1) <= r_regs(r_regs'left+1 to r_regs'right);
      r_regs(r_regs'right) <= p_in;
    end if;
  end process clock;

  p_out <= r_regs(r_regs'left);
  
end rtl;
