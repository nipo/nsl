library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.noc.all;
use nsl.util.all;
use nsl.testing.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal n0_val : noc_cmd_array(0 downto 0);
  signal n0_ack : noc_rsp_array(0 downto 0);

  signal n1_val : noc_cmd_array(0 downto 0);
  signal n1_ack : noc_rsp_array(0 downto 0);

  shared variable sim_end : boolean := false;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  router: nsl.noc.noc_router
    generic map(
      in_port_count => 1,
      out_port_count => 1,
      routing_table => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => n0_val,
      p_in_ack => n0_ack,
      p_out_val => n1_val,
      p_out_ack => n1_ack
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if not sim_end then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;
  
end;
