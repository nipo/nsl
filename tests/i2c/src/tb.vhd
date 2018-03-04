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

  signal s_scl : std_logic;
  signal s_sda : std_logic;
  signal s_scl_drain_m : std_ulogic;
  signal s_sda_drain_m : std_ulogic;
  signal s_scl_drain_s : std_ulogic;
  signal s_sda_drain_s : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_val_fifo, s_rsp_val_fifo : nsl.framed.framed_req;
  signal s_cmd_ack_fifo, s_rsp_ack_fifo : nsl.framed.framed_ack;
  signal s_i2c_cmd_val, s_i2c_rsp_val : nsl.framed.framed_req;
  signal s_i2c_cmd_ack, s_i2c_rsp_ack : nsl.framed.framed_ack;

  signal s_clk_gen, s_clk_gen_toggle: std_ulogic;

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  i2c_endpoint: nsl.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_val_fifo,
      p_cmd_in_ack => s_cmd_ack_fifo,
      p_rsp_out_val => s_rsp_val_fifo,
      p_rsp_out_ack => s_rsp_ack_fifo,
      
      p_cmd_out_val => s_i2c_cmd_val,
      p_cmd_out_ack => s_i2c_cmd_ack,
      p_rsp_in_val => s_i2c_rsp_val,
      p_rsp_in_ack => s_i2c_rsp_ack
      );

  master: nsl.i2c.i2c_framed_ctrl
    port map(
      p_clk  => s_clk,
      p_resetn => s_resetn_clk,
      
      p_cmd_val => s_i2c_cmd_val,
      p_cmd_ack => s_i2c_cmd_ack,
      p_rsp_val => s_i2c_rsp_val,
      p_rsp_ack => s_i2c_rsp_ack,
      
      p_scl => s_scl,
      p_sda => s_sda,
      p_sda_drain => s_sda_drain_m,
      p_scl_drain => s_scl_drain_m
      );

  i2c_mem: nsl.i2c.i2c_mem
    generic map(
      slave_addr => "0100110",
      mem_addr_width => 16
      )
    port map(
      p_clk  => s_clk,
      p_resetn => s_resetn_clk,
      
      p_scl => s_scl,
      p_sda => s_sda,
      p_sda_drain => s_sda_drain_s,
      p_scl_drain => s_scl_drain_s
      );

  s_scl <= '0' when s_scl_drain_s = '1' or s_scl_drain_m = '1' else '1';
  s_sda <= '0' when s_sda_drain_s = '1' or s_sda_drain_m = '1' else '1';

  gen: testing.framed.framed_file_reader
    generic map(
      filename => "i2c_commands.txt"
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
      filename => "i2c_responses.txt"
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
