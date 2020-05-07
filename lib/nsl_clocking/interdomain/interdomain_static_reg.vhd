library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interdomain_static_reg is
  generic(
    data_width_c : integer
    );
  port(
    input_clock_i : in  std_ulogic;
    data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    data_o  : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end interdomain_static_reg;

architecture rtl of interdomain_static_reg is
  
  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep     : string;
  attribute syn_keep : boolean;
  attribute nomerge  : string;

  signal tig_static_reg_d                : word_t;
  attribute keep of tig_static_reg_d     : signal is "TRUE";
  attribute syn_keep of tig_static_reg_d : signal is true;
  attribute nomerge of tig_static_reg_d  : signal is "";

begin

  clock : process(input_clock_i)
  begin
    if rising_edge(input_clock_i) then
      tig_static_reg_d <= data_i;
    end if;
  end process clock;

  data_o <= tig_static_reg_d;
  
end rtl;
