library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl;
library testing;
library util;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_srst : std_ulogic;
  signal s_dc : std_ulogic;
  signal s_ddoe : std_ulogic;
  signal s_ddo : std_ulogic;
  signal s_dd : std_logic;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_routed_cmd, s_routed_rsp : nsl.framed.framed_bus;
  signal s_cc_cmd, s_cc_rsp : nsl.framed.framed_bus;

  signal s_clk_gen, s_clk_gen_toggle: std_ulogic;

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.framed.framed_file_reader
    generic map(
      filename => "cc_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_routed_cmd.req,
      p_out_ack => s_routed_cmd.ack,
      p_done => s_done(0)
      );

  check0: testing.framed.framed_file_checker
    generic map(
      filename => "cc_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_routed_rsp.req,
      p_in_ack => s_routed_rsp.ack,
      p_done => s_done(1)
      );

  cc_endpoint: nsl.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_routed_cmd.req,
      p_cmd_in_ack => s_routed_cmd.ack,
      p_rsp_out_val => s_routed_rsp.req,
      p_rsp_out_ack => s_routed_rsp.ack,
      
      p_cmd_out_val => s_cc_cmd.req,
      p_cmd_out_ack => s_cc_cmd.ack,
      p_rsp_in_val => s_cc_rsp.req,
      p_rsp_in_ack => s_cc_rsp.ack
      );

  master: nsl.ti.ti_framed_cc
    port map(
      p_clk  => s_clk,
      p_resetn => s_resetn_clk,
      
      p_cmd_val => s_cc_cmd.req,
      p_cmd_ack => s_cc_cmd.ack,
      p_rsp_val => s_cc_rsp.req,
      p_rsp_ack => s_cc_rsp.ack,
      
      p_cc_resetn => s_srst,
      p_cc_dc => s_dc,
      p_cc_ddo => s_ddo,
      p_cc_ddoe => s_ddoe,
      p_cc_ddi => std_ulogic(s_dd)
      );

  s_dd <= '1' when s_ddoe = '1' else '1';

  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= "11" then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
