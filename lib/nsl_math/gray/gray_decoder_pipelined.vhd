library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

entity gray_decoder_pipelined is
  generic(
    cycle_count_c : natural;
    data_width_c : integer
    );
  port(
    clock_i : in std_ulogic;
    gray_i : in std_ulogic_vector(data_width_c-1 downto 0);
    binary_o : out unsigned(data_width_c-1 downto 0)
    );
end entity;

architecture rtl of gray_decoder_pipelined is

  constant group_by : natural := (data_width_c + cycle_count_c - 1) / cycle_count_c;
  constant word_width : natural := group_by * cycle_count_c + 1;
  subtype word_t is std_ulogic_vector(word_width - 1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  signal r_regs : word_vector_t (0 to cycle_count_c);
  
begin

  binary_o <= unsigned(r_regs(0)(binary_o'range));

  clock: process (clock_i, gray_i)
  begin
    r_regs(cycle_count_c)(word_width - 1 downto gray_i'length) <= (others => '0');
    r_regs(cycle_count_c)(gray_i'range) <= gray_i;
    if rising_edge(clock_i) then
      for i in 0 to cycle_count_c-1
      loop
        r_regs(i) <= r_regs(i+1);
        r_regs(i)((i+1) * group_by downto i * group_by)
          <= std_ulogic_vector(nsl_math.gray.gray_to_bin(r_regs(i+1)((i+1) * group_by downto i * group_by)));
        
      end loop;
    end if;
  end process clock;
  
  
end architecture;
