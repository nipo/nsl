library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_reg is
  generic(
    cycle_count : natural := 2;
    data_width : integer
    );
  port(
    p_clk : in std_ulogic;
    p_in  : in std_ulogic_vector(data_width-1 downto 0);
    p_out : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_reg;

architecture rtl of sync_reg is

  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type regs_t is array(cycle_count - 1 downto 0) of word_t;
  signal r_regs : regs_t;
  attribute keep : boolean;
  attribute keep of r_regs : signal is true;

begin

  clock: process (p_clk)
  begin
    if rising_edge(p_clk) then
      g: for i in 0 to cycle_count-2 loop
        r_regs(i) <= r_regs(i+1);
      end loop;
      r_regs(cycle_count-1) <= p_in;
    end if;
  end process clock;

  p_out <= r_regs(0);
  
end rtl;
