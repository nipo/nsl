library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_async_reg is
  generic(
    cycle_count : natural range 2 to 40 := 2;
    data_width : integer
    );
  port(
    p_clk    : in std_ulogic;
    p_in     : in std_ulogic_vector(data_width-1 downto 0);
    p_out    : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_async_reg;

architecture rtl of sync_async_reg is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep : string;
  attribute async_reg : string;
  attribute syn_keep : boolean;
  attribute nomerge : string;

  signal tig_reg_d : word_t;
  signal metastable_reg_d : word_vector_t (0 to cycle_count-2);
  attribute keep of tig_reg_d, metastable_reg_d : signal is "TRUE";
  attribute syn_keep of tig_reg_d, metastable_reg_d : signal is true;
  attribute async_reg of tig_reg_d, metastable_reg_d : signal is "TRUE";
  attribute nomerge of tig_reg_d, metastable_reg_d : signal is "";
begin

  clock: process (p_clk)
  begin
    if rising_edge(p_clk) then
      metastable_reg_d
        <= metastable_reg_d(1 to metastable_reg_d'high) & tig_reg_d;
      tig_reg_d <= p_in;
    end if;
  end process clock;

  p_out <= metastable_reg_d(metastable_reg_d'left);
  
end rtl;
