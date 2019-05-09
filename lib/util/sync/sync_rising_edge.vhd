library ieee;
use ieee.std_logic_1164.all;

entity sync_rising_edge is
  generic(
    cycle_count : natural := 2;
    async_reset : boolean := true
    );
  port(
    p_in  : in  std_ulogic;
    p_clk : in  std_ulogic;
    p_out : out std_ulogic
    );

end sync_rising_edge;

architecture rtl of sync_rising_edge is

  attribute keep : string;

begin

  sync: if not async_reset
  generate
    signal tig_reg_d : std_ulogic_vector(0 to cycle_count-1);
    attribute keep of tig_reg_d : signal is "TRUE";
  begin
    rst: process (p_clk, p_in)
    begin
      if rising_edge(p_clk) then
        if p_in = '0' then
          tig_reg_d <= (others => '0');
        else
          tig_reg_d <= tig_reg_d(1 to cycle_count - 1) & '1';
        end if;
      end if;
    end process;

    p_out <= '1' when tig_reg_d = (tig_reg_d'range => '1') else '0';
  end generate;

  async: if async_reset
  generate
    signal tig_reg_clr : std_ulogic_vector(0 to cycle_count-1);
    attribute keep of tig_reg_clr : signal is "TRUE";
  begin
    rst: process (p_clk, p_in)
    begin
      if p_in = '0' then
        tig_reg_clr <= (others =>'0');
      elsif rising_edge(p_clk) then
        tig_reg_clr <= tig_reg_clr(1 to cycle_count - 1) & '1';
      end if;
    end process;

    p_out <= '1' when tig_reg_clr = (tig_reg_clr'range => '1') else '0';
  end generate;

  
end rtl;
