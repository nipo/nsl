library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation;
use nsl_jtag.jtag.all;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_fifo, s_rsp_fifo : nsl_bnoc.framed.framed_bus;
  signal s_cmd_ate, s_rsp_ate : nsl_bnoc.framed.framed_bus;

  signal s_tap_ir : std_ulogic_vector(3 downto 0);
  signal s_tap_reset, s_tap_run, s_tap_dr_capture,
    s_tap_dr_shift, s_tap_dr_update, s_tap_dr_in, s_tap_dr_out : std_ulogic;
  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  signal s_idcode_out, s_idcode_selected : std_ulogic;
  signal s_bypass_out, s_bypass_selected : std_ulogic;

  signal s_clk_gen, s_clk_gen_toggle: std_ulogic;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  ate_endpoint: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_fifo.req,
      p_cmd_in_ack => s_cmd_fifo.ack,
      p_rsp_out_val => s_rsp_fifo.req,
      p_rsp_out_ack => s_rsp_fifo.ack,
      
      p_cmd_out_val => s_cmd_ate.req,
      p_cmd_out_ack => s_cmd_ate.ack,
      p_rsp_in_val => s_rsp_ate.req,
      p_rsp_in_ack => s_rsp_ate.ack
      );

  master: nsl_jtag.transactor.framed_ate
    port map(
      clock_i  => s_clk,
      reset_n_i => s_resetn_clk,

      cmd_i => s_cmd_ate.req,
      cmd_o => s_cmd_ate.ack,
      rsp_o => s_rsp_ate.req,
      rsp_i => s_rsp_ate.ack,

      jtag_o => ate_o,
      jtag_i => ate_i
      );

  ate_i <= to_ate(tap_o);
  tap_i <= to_tap(ate_o);
  
  tap: nsl_jtag.tap.tap_port
    generic map(
      ir_len => 4
      )
    port map(
      jtag_i => tap_i,
      jtag_o => tap_o,

      default_instruction_i => "0010",

      ir_o => s_tap_ir,
      ir_out_i => "00",
      reset_o => s_tap_reset,
      run_o => s_tap_run,
      dr_capture_o => s_tap_dr_capture,
      dr_shift_o => s_tap_dr_shift,
      dr_update_o => s_tap_dr_update,
      dr_tdi_o => s_tap_dr_in,
      dr_tdo_i => s_tap_dr_out
      );

  idcode: nsl_jtag.tap.tap_dr
    generic map(
      ir_len => 4,
      dr_len => 32
      )
    port map(
      tck_i => tap_i.tck,
      tdi_i => s_tap_dr_in,
      tdo_o => s_idcode_out,

      match_ir_i => "0010",
      current_ir_i => s_tap_ir,
      active_o => s_idcode_selected,

      dr_capture_i => s_tap_dr_capture,
      dr_shift_i => s_tap_dr_shift,
      value_o => open,
      value_i => x"87654321"
      );

  bypass: nsl_jtag.tap.tap_dr
    generic map(
      ir_len => 4,
      dr_len => 1
      )
    port map(
      tck_i => tap_i.tck,
      tdi_i => s_tap_dr_in,
      tdo_o => s_bypass_out,

      match_ir_i => "1111",
      current_ir_i => s_tap_ir,
      active_o => s_bypass_selected,

      dr_capture_i => s_tap_dr_capture,
      dr_shift_i => s_tap_dr_shift,
      value_o => open,
      value_i => "0"
      );

  tdo_gen: process(s_idcode_selected, s_idcode_out,
                   s_bypass_selected, s_bypass_out)
  begin
    s_tap_dr_out <= '-';

    if s_idcode_selected = '1' then
      s_tap_dr_out <= s_idcode_out;
    elsif s_bypass_selected = '1' then
      s_tap_dr_out <= s_bypass_out;
    end if;
  end process;
  

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "ate_commands.txt"
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
      filename => "ate_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_fifo.req,
      p_in_ack => s_rsp_fifo.ack,
      p_done => s_done(1)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
