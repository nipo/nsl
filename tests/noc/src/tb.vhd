library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.noc.all;
use nsl.util.all;

library testing;
use testing.noc.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic;

  signal n0_val : noc_cmd_array(0 downto 0);
  signal n0_ack : noc_rsp_array(0 downto 0);
  signal n1_val : noc_cmd_array(1 downto 0);
  signal n1_ack : noc_rsp_array(1 downto 0);

  shared variable sim_end : boolean := false;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.noc.noc_file_reader
    generic map(
      filename => "input_0.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => n0_val(0),
      p_out_ack => n0_ack(0),
      p_done => s_done
      );

  check0: testing.noc.noc_file_checker
    generic map(
      filename => "output_0.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => n1_val(0),
      p_in_ack => n1_ack(0)
      );

  check1: testing.noc.noc_file_checker
    generic map(
      filename => "output_1.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_ack => n1_ack(1),
      p_in_val => n1_val(1)
      );

  router: nsl.noc.noc_router
    generic map(
      in_port_count => 1,
      out_port_count => 2,
      routing_table => (0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
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
    wait until rising_edge(s_done);
    sim_end := true;
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if not sim_end then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;
  
end;
