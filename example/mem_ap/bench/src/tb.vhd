library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_coresight, main;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_swd_master_o : nsl_coresight.swd.swd_master_o;
  signal s_swd_master_i : nsl_coresight.swd.swd_master_i;
  signal swdio: std_logic;
  signal s_srst : std_logic;

  signal s_ap_resetn : std_ulogic;
  signal s_ap_sel : unsigned(7 downto 0);
  signal s_ap_a : unsigned(5 downto 0);
  signal s_ap_rdata : unsigned(31 downto 0);
  signal s_ap_ready : std_ulogic;
  signal s_ap_rok : std_ulogic;
  signal s_ap_ren : std_ulogic;
  signal s_ap_wdata : unsigned(31 downto 0);
  signal s_ap_wen : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_fifo, s_rsp_fifo : nsl_bnoc.framed.framed_bus;
  signal s_cmd_swd, s_rsp_swd : nsl_bnoc.framed.framed_bus;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  swdio <= s_swd_master_o.dio.v when s_swd_master_o.dio.en = '1' else 'Z';
  swdio <= 'H';
  s_swd_master_i.dio <= swdio;

  dap: main.topcell.top
    port map(
      swclk => s_swd_master_o.clk,
      swdio => swdio
      );
  
  swd_endpoint: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_fifo.req,
      p_cmd_in_ack => s_cmd_fifo.ack,
      p_rsp_out_val => s_rsp_fifo.req,
      p_rsp_out_ack => s_rsp_fifo.ack,
      
      p_cmd_out_val => s_cmd_swd.req,
      p_cmd_out_ack => s_cmd_swd.ack,
      p_rsp_in_val => s_rsp_swd.req,
      p_rsp_in_ack => s_rsp_swd.ack
      );

  dp: nsl_coresight.dp.dp_framed_swdp
    port map(
      p_clk  => s_clk,
      p_resetn => s_resetn_clk,
      
      p_cmd_val => s_cmd_swd.req,
      p_cmd_ack => s_cmd_swd.ack,

      p_rsp_val => s_rsp_swd.req,
      p_rsp_ack => s_rsp_swd.ack,

      p_swd_o => s_swd_master_o,
      p_swd_i => s_swd_master_i
      );

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_fifo.req,
      p_out_ack => s_cmd_fifo.ack,
      p_done => s_done(0)
      );

  check0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_fifo.req,
      p_in_ack => s_rsp_fifo.ack,
      p_done => s_done(1)
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
    if s_done /= "11" then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;