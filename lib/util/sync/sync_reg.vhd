library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_reg is
  generic(
    cycle_count : natural := 2;
    data_width : integer;
    cross_region : boolean := true
    );
  port(
    p_clk    : in std_ulogic;
    p_in     : in std_ulogic_vector(data_width-1 downto 0);
    p_out    : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_reg;

architecture rtl of sync_reg is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type regs_t is array(0 to cycle_count - 1) of word_t;
  attribute keep : string;
  attribute async_reg : string;

begin

  cross: if cross_region generate
    signal tig_reg : regs_t;
    attribute keep of tig_reg : signal is "TRUE";
    attribute async_reg of tig_reg : signal is "TRUE";
  begin
    clock: process (p_clk)
    begin
      if rising_edge(p_clk) then
        tig_reg(0 to cycle_count-2) <= tig_reg(1 to cycle_count-1);
        tig_reg(cycle_count-1) <= p_in;
      end if;
    end process clock;

    p_out <= tig_reg(0);
  end generate cross;

  nocross: if not cross_region generate
    signal r_regs : regs_t;
  begin
    clock: process (p_clk)
    begin
      if rising_edge(p_clk) then
        r_regs(0 to cycle_count-2) <= r_regs(1 to cycle_count-1);
        r_regs(cycle_count-1) <= p_in;
      end if;
    end process clock;

    p_out <= r_regs(0);
  end generate nocross;
  
end rtl;
