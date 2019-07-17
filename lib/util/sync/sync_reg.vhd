library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity sync_reg is
  generic(
    cycle_count : natural range 1 to 40 := 2;
    data_width : integer;
    cross_region : boolean := true;
    async_sampler : boolean := false
    );
  port(
    p_clk    : in std_ulogic;
    p_in     : in std_ulogic_vector(data_width-1 downto 0);
    p_out    : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_reg;

architecture rtl of sync_reg is
begin
  
  cross: if cross_region generate
  begin
    assert false
      report "util.sync.sync_reg component is deprecated, you should consider moving to util.sync.sync_cross_reg"
      severity warning;

    assert cycle_count >= 2
      report "util.sync.sync_reg(cross_region) can only handle cycle_count >= 2"
      severity error;

    impl: util.sync.sync_cross_reg
      generic map(
        cycle_count => cycle_count,
        data_width => data_width
        )
      port map(
        p_clk => p_clk,
        p_in => p_in,
        p_out => p_out
        );
  end generate cross;

  async: if async_sampler and not cross_region generate
  begin
    assert false
      report "util.sync.sync_reg component is deprecated, you should consider moving to util.sync.sync_async_reg"
      severity warning;

    assert cycle_count >= 2
      report "util.sync.sync_reg(async_sampler) can only handle cycle_count >= 2"
      severity error;

    impl: util.sync.sync_async_reg
      generic map(
        cycle_count => cycle_count,
        data_width => data_width
        )
      port map(
        p_clk => p_clk,
        p_in => p_in,
        p_out => p_out
        );
  end generate async;

  nocross: if not cross_region and not async_sampler generate
  begin
    assert false
      report "util.sync.sync_reg component is deprecated, you should consider moving to util.sync.sync_multi_reg"
      severity warning;

    impl: util.sync.sync_multi_reg
      generic map(
        cycle_count => cycle_count,
        data_width => data_width
        )
      port map(
        p_clk => p_clk,
        p_in => p_in,
        p_out => p_out
        );
  end generate nocross;
  
end rtl;
