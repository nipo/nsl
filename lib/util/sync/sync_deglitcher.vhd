library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity sync_deglitcher is

  generic(
    cycle_count : natural := 2
    );
  port (
    p_clk : in  std_ulogic;
    p_in  : in  std_ulogic;
    p_out : out std_ulogic
    );

end sync_deglitcher;

architecture rtl of sync_deglitcher is

begin

  shreg: if cycle_count < 4
  generate
    signal r_backlog : std_ulogic_vector(0 to cycle_count-1);
    signal r_value : std_ulogic;
  begin
    reg: process (p_clk)
    begin
      if rising_edge(p_clk) then
        r_backlog <= p_in & r_backlog(r_backlog'left to r_backlog'right-1);

        if r_backlog = (r_backlog'range => '1') then
          r_value <= '1';
        elsif r_backlog = (r_backlog'range => '0') then
          r_value <= '0';
        end if;
      end if;
    end process;

    p_out <= r_value;
  end generate;

  counter: if cycle_count >= 4
  generate
    signal r_counter : unsigned(util.numeric.log2(cycle_count) downto 0) := (others => '0');
  begin
    reg: process (p_clk)
    begin
      if rising_edge(p_clk) then
        if p_in = '1' and r_counter /= (r_counter'range => '1') then
          r_counter <= r_counter + 1;
        elsif p_in = '0' and r_counter /= (r_counter'range => '0') then
          r_counter <= r_counter - 1;
        end if;
      end if;
    end process;

    p_out <= r_counter(r_counter'left);
  end generate;

end rtl;
