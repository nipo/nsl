library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.noc.all;
use nsl.flit.all;
use nsl.util.all;
use nsl.ti.all;

library testing;
use testing.flit.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(1 downto 0);
  signal s_all_done : std_ulogic;

  signal s_easyscale : std_ulogic;

  signal s_cmd_val : flit_cmd;
  signal s_cmd_ack : flit_ack;
  signal s_rsp_val : flit_cmd;
  signal s_rsp_ack : flit_ack;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.flit.flit_file_reader
    generic map(
      filename => "ez_cmd.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_val,
      p_out_ack => s_cmd_ack,
      p_done => s_done(0)
      );

  check0: testing.flit.flit_file_checker
    generic map(
      filename => "ez_rsp.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_val,
      p_in_ack => s_rsp_ack,
      p_done => s_done(1)
      );

  ez: ti_easyscale_noc
    generic map(
      p_clk_rate => 100000000
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_easyscale => s_easyscale,
      p_cmd_val => s_cmd_val,
      p_cmd_ack => s_cmd_ack,
      p_rsp_val => s_rsp_val,
      p_rsp_ack => s_rsp_ack
      );
  
  s_all_done <= s_done(0) and s_done(1);
  
  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_all_done /= '1' then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;
  
end;
