library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_static_reg is
  generic(
    data_width : integer
    );
  port(
    p_clk     : in std_ulogic;
    p_in      : in std_ulogic_vector(data_width-1 downto 0);
	p_out     : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_static_reg;

architecture rtl of sync_static_reg is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep : string;
  attribute syn_keep : boolean;
  attribute nomerge : string;

  signal tig_static_reg_d : word_t;
  attribute keep of tig_static_reg_d : signal is "TRUE";
  attribute syn_keep of tig_static_reg_d : signal is true;
  attribute nomerge of tig_static_reg_d : signal is "";
begin

  clock: process (p_clk)
  begin
    if rising_edge(p_clk) then
      tig_static_reg_d <= p_in;
    end if;
  end process clock;

  p_out <= tig_static_reg_d;
  
end rtl;
