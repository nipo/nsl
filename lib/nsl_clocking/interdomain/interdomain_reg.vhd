library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interdomain_reg is
  generic(
    stable_count_c : natural := 0;
    cycle_count_c : natural range 2 to 40 := 2;
    data_width_c : integer
    );
  port(
    clock_i    : in std_ulogic;
    data_i     : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o    : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end interdomain_reg;

architecture rtl of interdomain_reg is
  
  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep : string;
  attribute async_reg : string;
  attribute syn_preserve : boolean;
  attribute nomerge : string;

  signal stable_s : natural range 0 to stable_count_c;
  signal stable_d, cross_region_reg_d : word_t;
  signal metastable_reg_d : word_vector_t (0 to cycle_count_c-2);
  attribute keep of cross_region_reg_d, metastable_reg_d : signal is "TRUE";
  attribute async_reg of cross_region_reg_d, metastable_reg_d : signal is "TRUE";
  attribute syn_preserve of cross_region_reg_d, metastable_reg_d : signal is true;
  attribute nomerge of cross_region_reg_d, metastable_reg_d : signal is "TRUE";

begin

  clock: process (clock_i)
    variable last_val, cur_val : word_t;
  begin
    if rising_edge(clock_i) then
      metastable_reg_d
        <= metastable_reg_d(1 to metastable_reg_d'high)
        & cross_region_reg_d;
      cross_region_reg_d <= data_i;
      
      if cycle_count_c = 2 then
        last_val := cross_region_reg_d;
      else
        last_val := metastable_reg_d(metastable_reg_d'left+1);
      end if;
      cur_val := metastable_reg_d(metastable_reg_d'left);
      
      if stable_count_c /= 0 and last_val /= cur_val then
        stable_s <= stable_count_c - 1;
      elsif stable_s = 0 or stable_count_c = 0 then
        stable_d <= cur_val;
      else
        stable_s <= stable_s - 1;
      end if;

    end if;
  end process clock;
    
  data_o <= metastable_reg_d(metastable_reg_d'left) when stable_count_c = 0 else stable_d;
  
end rtl;
