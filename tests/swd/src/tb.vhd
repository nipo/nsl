library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl;
use nsl.util.all;
use nsl.noc.all;
use nsl.swd.all;

library testing;
use testing.swd.all;
use testing.noc.all;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_swclk : std_logic;
  signal s_swdio : std_logic;

  signal s_dap_a : unsigned(1 downto 0);
  signal s_dap_ad : std_logic;
  signal s_dap_rdata : unsigned(31 downto 0);
  signal s_dap_ready : std_logic;
  signal s_dap_ren : std_logic;
  signal s_dap_wdata : unsigned(31 downto 0);
  signal s_dap_wen : std_logic;

  signal s_in_val    : noc_cmd;
  signal s_in_ack    : noc_rsp;
  signal s_out_val   : noc_cmd;
  signal s_out_ack   : noc_rsp;
  signal s_swdio_o   : std_ulogic;
  signal s_swdio_oe  : std_ulogic;

  signal s_done : std_ulogic;
  shared variable sim_end : boolean := false;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  swdap: testing.swd.swdap
    port map(
      p_swclk => s_swclk,
      p_swdio => s_swdio,
      p_dap_a => s_dap_a,
      p_dap_ad => s_dap_ad,
      p_dap_rdata => s_dap_rdata,
      p_dap_ready => s_dap_ready,
      p_dap_ren => s_dap_ren,
      p_dap_wdata => s_dap_wdata,
      p_dap_wen => s_dap_wen
      );

  dap: testing.swd.dap_sim
    port map(
      p_clk => s_swclk,
      p_dap_a => s_dap_a,
      p_dap_ad => s_dap_ad,
      p_dap_rdata => s_dap_rdata,
      p_dap_ready => s_dap_ready,
      p_dap_ren => s_dap_ren,
      p_dap_wdata => s_dap_wdata,
      p_dap_wen => s_dap_wen
      );

  swd_master: nsl.swd.swd_master
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_in_val => s_in_val,
      p_in_ack => s_in_ack,
      p_out_val => s_out_val,
      p_out_ack => s_out_ack,

      p_swclk => s_swclk,
      p_swdio_o => s_swdio_o,
      p_swdio_i => s_swdio,
      p_swdio_oe => s_swdio_oe
      );

  s_swdio <= s_swdio_o when s_swdio_oe = '1' else 'Z';

  gen: testing.noc.noc_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_in_val,
      p_out_ack => s_in_ack,
      p_done => s_done
      );

  check0: testing.noc.noc_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_out_val,
      p_in_ack => s_out_ack
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait until rising_edge(s_done);
    wait for 800 ns;
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
