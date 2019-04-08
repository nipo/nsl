library ieee;
use ieee.std_logic_1164.all;

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

end rtl;
