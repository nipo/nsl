library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl;
library testing;
library coresight;
library util;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_swclk : std_ulogic;
  signal s_swdio : std_logic;
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

  signal s_swdio_o   : std_ulogic;
  signal s_swdio_oe  : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_val_fifo, s_rsp_val_fifo : nsl.framed.framed_req;
  signal s_cmd_ack_fifo, s_rsp_ack_fifo : nsl.framed.framed_ack;
  signal s_swd_cmd_val, s_swd_rsp_val : nsl.framed.framed_req;
  signal s_swd_cmd_ack, s_swd_rsp_ack : nsl.framed.framed_ack;

  signal s_clk_gen, s_clk_gen_toggle: std_ulogic;

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  swdap: testing.swd.swdap
    port map(
      p_swclk => s_swclk,
      p_swdio => s_swdio,

      p_swd_resetn => s_ap_resetn,
      p_ap_sel => s_ap_sel,
      p_ap_a => s_ap_a,
      p_ap_rdata => s_ap_rdata,
      p_ap_ready => s_ap_ready,
      p_ap_ren => s_ap_ren,
      p_ap_rok => s_ap_rok,
      p_ap_wdata => s_ap_wdata,
      p_ap_wen => s_ap_wen
      );

  ap: testing.swd.ap_sim
    port map(
      p_clk => s_swclk,
      p_resetn => s_ap_resetn,
      p_ap => s_ap_sel,
      p_a => s_ap_a,
      p_rdata => s_ap_rdata,
      p_ready => s_ap_ready,
      p_ren => s_ap_ren,
      p_rok => s_ap_rok,
      p_wdata => s_ap_wdata,
      p_wen => s_ap_wen
      );

  swd_endpoint: nsl.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_val_fifo,
      p_cmd_in_ack => s_cmd_ack_fifo,
      p_rsp_out_val => s_rsp_val_fifo,
      p_rsp_out_ack => s_rsp_ack_fifo,
      
      p_cmd_out_val => s_swd_cmd_val,
      p_cmd_out_ack => s_swd_cmd_ack,
      p_rsp_in_val => s_swd_rsp_val,
      p_rsp_in_ack => s_swd_rsp_ack
      );

  dp: coresight.dp.dp_framed_swdp
    port map(
      p_clk  => s_clk,
      p_resetn => s_resetn_clk,

      p_clk_ref => s_clk_gen,
      
      p_cmd_val => s_swd_cmd_val,
      p_cmd_ack => s_swd_cmd_ack,

      p_rsp_val => s_swd_rsp_val,
      p_rsp_ack => s_swd_rsp_ack,
      
      p_swclk => s_swclk,
      p_swdio_i => s_swdio,
      p_swdio_o => s_swdio_o,
      p_swdio_oe => s_swdio_oe
      );

  baud_gen: nsl.tick.baudrate_generator
    generic map(
      p_clk_rate => 200000000,
      rate_lsb => 0,
      rate_msb => 27
      )
    port map(
      p_clk => s_clk,
      p_resetn => s_resetn_clk,
      p_rate => X"01fffff",
      p_tick => s_clk_gen_toggle
      );

  process(s_clk, s_resetn_clk, s_clk_gen_toggle)
  begin
    if s_resetn_clk = '0' then
      s_clk_gen <= '0';
    elsif rising_edge(s_clk) then
      if s_clk_gen_toggle = '1' then
        s_clk_gen <= not s_clk_gen;
      end if;
    end if;
  end process;

  s_swdio <= s_swdio_o when s_swdio_oe = '1' else 'Z';

  gen: testing.framed.framed_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_val_fifo,
      p_out_ack => s_cmd_ack_fifo,
      p_done => s_done(0)
      );

  check0: testing.framed.framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_val_fifo,
      p_in_ack => s_rsp_ack_fifo,
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
