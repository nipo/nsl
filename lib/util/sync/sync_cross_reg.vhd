library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_cross_reg is
  generic(
    stable_count : natural := 0;
    cycle_count : natural range 2 to 40 := 2;
    data_width : integer
    );
  port(
    p_clk    : in std_ulogic;
    p_in     : in std_ulogic_vector(data_width-1 downto 0);
    p_out    : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_cross_reg;

architecture rtl of sync_cross_reg is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep : string;
  attribute async_reg : string;
  attribute syn_keep : boolean;
  attribute nomerge : string;

  signal stable_s : natural range 0 to stable_count;
  signal stable_d, cross_region_reg_d : word_t;
  signal metastable_reg_d : word_vector_t (0 to cycle_count-2);
  attribute keep of cross_region_reg_d, metastable_reg_d : signal is "TRUE";
  attribute async_reg of cross_region_reg_d, metastable_reg_d : signal is "TRUE";
  attribute syn_keep of cross_region_reg_d, metastable_reg_d : signal is true;
  attribute nomerge of cross_region_reg_d, metastable_reg_d : signal is "";

begin

  clock: process (p_clk)
    variable last_val, cur_val : word_t;
  begin
    if rising_edge(p_clk) then
      metastable_reg_d
        <= metastable_reg_d(1 to metastable_reg_d'high)
        & cross_region_reg_d;
      cross_region_reg_d <= p_in;
      
	  if cycle_count = 2 then
	    last_val := cross_region_reg_d;
	  else
	    last_val := metastable_reg_d(metastable_reg_d'left+1);
	  end if;
	  cur_val := metastable_reg_d(metastable_reg_d'left);
	
	  if last_val /= cur_val then
	    stable_s <= stable_count - 1;
	  elsif stable_s = 0 then
        stable_d <= cur_val;
	  else
	    stable_s <= stable_s - 1;
	  end if;

    end if;
  end process clock;
    
  p_out <= metastable_reg_d(metastable_reg_d'left) when stable_count = 0 else stable_d;
  
end rtl;
