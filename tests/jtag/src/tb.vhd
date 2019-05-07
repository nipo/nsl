library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl, testing, util;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_tdi, s_tdo, s_tms, s_tck: std_ulogic;
  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_val_fifo, s_rsp_val_fifo : nsl.framed.framed_req;
  signal s_cmd_ack_fifo, s_rsp_ack_fifo : nsl.framed.framed_ack;
  signal s_ate_cmd_val, s_ate_rsp_val : nsl.framed.framed_req;
  signal s_ate_cmd_ack, s_ate_rsp_ack : nsl.framed.framed_ack;

  signal s_tap_ir : std_ulogic_vector(3 downto 0);
  signal s_tap_reset, s_tap_run, s_tap_dr_capture,
    s_tap_dr_shift, s_tap_dr_update, s_tap_dr_in, s_tap_dr_out : std_ulogic;
  signal s_idcode_out, s_idcode_selected : std_ulogic;
  signal s_bypass_out, s_bypass_selected : std_ulogic;

  signal s_clk_gen, s_clk_gen_toggle: std_ulogic;

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  ate_endpoint: nsl.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_val_fifo,
      p_cmd_in_ack => s_cmd_ack_fifo,
      p_rsp_out_val => s_rsp_val_fifo,
      p_rsp_out_ack => s_rsp_ack_fifo,
      
      p_cmd_out_val => s_ate_cmd_val,
      p_cmd_out_ack => s_ate_cmd_ack,
      p_rsp_in_val => s_ate_rsp_val,
      p_rsp_in_ack => s_ate_rsp_ack
      );

  master: nsl.jtag.jtag_framed_ate
    port map(
      clock_i  => s_clk,
      reset_n_i => s_resetn_clk,
      
      cmd_i => s_ate_cmd_val,
      cmd_o => s_ate_cmd_ack,
      rsp_o => s_ate_rsp_val,
      rsp_i => s_ate_rsp_ack,
      
      tck_o => s_tck,
      tdi_o => s_tdi,
      tdo_i => s_tdo,
      tms_o => s_tms
      );

  tap: nsl.jtag.jtag_tap
    generic map(
      ir_len => 4
      )
    port map(
      tck_i => s_tck,
      tdi_i => s_tdi,
      tdo_o => s_tdo,
      tms_i => s_tms,

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

  idcode: nsl.jtag.jtag_tap_dr
    generic map(
      ir_len => 4,
      dr_len => 32
      )
    port map(
      tck_i => s_tck,
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

  bypass: nsl.jtag.jtag_tap_dr
    generic map(
      ir_len => 4,
      dr_len => 1
      )
    port map(
      tck_i => s_tck,
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
  
  gen: testing.framed.framed_file_reader
    generic map(
      filename => "ate_commands.txt"
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
      filename => "ate_responses.txt"
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
    if s_done = (s_done'range => '1') then
      assert false report "all done" severity note;
    else
      s_clk <= not s_clk after 50 ns;
    end if;
  end process;

end;
