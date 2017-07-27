library ieee;
use ieee.std_logic_1164.all;

library util;
use util.sync.sync_rising_edge;

entity sync_multi_resetn is
  generic(
    cycle_count : natural := 2;
    clk_count : natural
    );
  port (
    p_clk : in  std_ulogic_vector(0 to clk_count-1);
    p_resetn  : in  std_ulogic;
    p_resetn_sync : out std_ulogic_vector(0 to clk_count-1)
    );
end sync_multi_resetn;

architecture rtl of sync_multi_resetn is

  signal common : std_ulogic_vector(0 to clk_count-1) := (others => '0');
  signal merged : std_ulogic := '0';

begin

  byport: for i in 0 to clk_count - 1 generate
    sync_in: util.sync.sync_rising_edge
      port map(
        p_in => p_resetn,
        p_clk => p_clk(i),
        p_out => common(i)
        );

    sync_out: util.sync.sync_rising_edge
      port map(
        p_in => merged,
        p_clk => p_clk(i),
        p_out => p_resetn_sync(i)
        );
  end generate;

  merged <= '1' when common = (common'range => '1') else '0';

end rtl;
