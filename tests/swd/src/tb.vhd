library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl;
use nsl.util.all;
use nsl.swd.all;

library testing;
use testing.swd.all;
use testing.fifo.all;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_swclk : std_ulogic;
  signal s_swdio : std_logic;
  signal s_srst : std_logic;

  signal s_dap_a : unsigned(1 downto 0);
  signal s_dap_ad : std_ulogic;
  signal s_dap_rdata : unsigned(31 downto 0);
  signal s_dap_ready : std_ulogic;
  signal s_dap_ren : std_ulogic;
  signal s_dap_wdata : unsigned(31 downto 0);
  signal s_dap_wen : std_ulogic;

  signal s_swdio_o   : std_ulogic;
  signal s_swdio_oe  : std_ulogic;

  signal s_done : std_ulogic;

  signal s_cmd_val_fifo, s_rsp_val_fifo : nsl.fifo.fifo_framed_cmd;
  signal s_cmd_ack_fifo, s_rsp_ack_fifo : nsl.fifo.fifo_framed_rsp;
  
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

  swdp_inst: nsl.swd.swd_swdp
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_val => s_cmd_val_fifo,
      p_cmd_ack => s_cmd_ack_fifo,
      p_rsp_val => s_rsp_val_fifo,
      p_rsp_ack => s_rsp_ack_fifo,
      
      p_srst => s_srst,
      p_swclk => s_swclk,
      p_swdio_o => s_swdio_o,
      p_swdio_i => s_swdio,
      p_swdio_oe => s_swdio_oe
      );

  s_swdio <= s_swdio_o when s_swdio_oe = '1' else 'Z';

  gen: testing.fifo.fifo_framed_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_val_fifo,
      p_out_ack => s_cmd_ack_fifo,
      p_done => open
      );

  check0: testing.fifo.fifo_framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_val_fifo,
      p_in_ack => s_rsp_ack_fifo,
      p_done => s_done
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= '1' then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
