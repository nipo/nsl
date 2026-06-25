library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_jtag, nsl_amba, nsl_simulation, nsl_data, nsl_event, nsl_math;


architecture arch of tb is

  constant cfg_c: nsl_amba.axi4_stream.config_t := nsl_amba.axi4_stream.config(1, last => true);

  signal s_cmd           : nsl_amba.axi4_stream.bus_t;
  signal s_rsp           : nsl_amba.axi4_stream.bus_t;

  signal s_tap_ir : std_ulogic_vector(3 downto 0);
  signal s_tap_reset, s_tap_run, s_tap_dr_capture, s_tap_dr_shift, s_tap_dr_update, s_tap_dr_in, s_tap_dr_out : std_ulogic;
  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  signal s_idcode_out, s_idcode_selected : std_ulogic;
  signal s_bypass_out, s_bypass_selected : std_ulogic;

  signal s_clk, s_resetn : std_ulogic;
  signal s_done : std_ulogic_vector(0 to 0);

  signal   tick_s, tick_ms_s: std_ulogic;
  constant tick_divisor: unsigned(7 downto 0) := (others => '1');
  constant tick_ms_divisor : unsigned := nsl_math.arith.to_unsigned_auto(10e7/1000);

begin

  ate_i <= nsl_jtag.jtag.to_ate(tap_o);
  tap_i <= nsl_jtag.jtag.to_tap(ate_o);
  
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

  dut: nsl_jtag.cbor_transactor.axi4stream_cbor_ate
  generic map(
    stream_config_c=> cfg_c
    )
  port map(
    clock_i  =>  s_clk,
    reset_n_i => s_resetn,

    tick_i => tick_s,
    tick_ms_i => tick_ms_s,
    
    cmd_i => s_cmd.m,
    cmd_o => s_cmd.s,

    rsp_o => s_rsp.m,
    rsp_i => s_rsp.s,
    
    jtag_o => ate_o,
    jtag_i => ate_i
    );

  net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
  generic map(
    config_c => cfg_c,
    bind_port_c => 4242
    )
  port map(
    clock_i => s_clk,
    reset_n_i => s_resetn,

    tx_i => s_rsp.m,
    tx_o => s_rsp.s,

    rx_o => s_cmd.m,
    rx_i => s_cmd.s
    );
      
  driver: nsl_simulation.driver.simulation_driver
  generic map(
    clock_count => 1,
    reset_count => 1,
    done_count => 1
    )
  port map(
    clock_period(0) => 10 ns,
    reset_duration(0) => 30 ns,
    reset_n_o(0) => s_resetn,
    clock_o(0) => s_clk,
    done_i => s_done
    );

  rx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      prefix_c => "UDP RX",
      config_c => cfg_c
      )
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      bus_i => s_cmd
      );

  tx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      prefix_c => "UDP TX",
      config_c => cfg_c
      )
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      bus_i => s_rsp
      );

  tick_gen: nsl_event.tick.tick_generator_integer
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      period_m1_i => tick_divisor,
      tick_o => tick_s
      );

  tick_ms_gen : nsl_event.tick.tick_generator_integer
    port map(
      clock_i     => s_clk,
      reset_n_i   => s_resetn,
      period_m1_i => tick_ms_divisor,
      tick_o      => tick_ms_s
    );

end architecture;
