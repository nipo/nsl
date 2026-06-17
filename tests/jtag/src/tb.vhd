library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation, nsl_data, nsl_math;
use nsl_jtag.jtag.all;
use nsl_jtag.transactor.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

architecture arch of tb is

  constant idcode_c : std_ulogic_vector(31 downto 0) := x"87654321";
  
  signal done_s : std_ulogic_vector(0 to 0);

  type framed_io is
  record
    cmd, rsp: nsl_bnoc.framed.framed_bus;
  end record;

  -- From host to ATE, abstract as framed queue
  shared variable command_q, response_q: framed_queue_root;

  -- From ATE to TAP
  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  shared variable cmd_delay, rsp_delay: time := 0 ns;
  
begin

  -- Abstract transactor
  host: process
    procedure do_io(response: out byte_stream; command: in byte_string)
    is
    begin
      framed_queue_put(command_q, command);
      framed_queue_get(response_q, response);
    end procedure;

    procedure chain_reset(div: integer range 1 to 256)
    is
      variable response: byte_stream;
    begin
      do_io(response, cmd_reset(5) & cmd_divisor(div) & cmd_reset(5) & cmd_run(1));
    end procedure;

    procedure div_set(div: integer range 1 to 256)
    is
      variable response: byte_stream;
    begin
      do_io(response, cmd_divisor(div));
    end procedure;

    procedure ir_set(ir: std_ulogic_vector)
    is
      variable command, response: byte_stream;
    begin
      command := null;

      write(command, cmd_capture_ir);
      write(command, cmd_shift(ir, false));
      write(command, cmd_run(1));

      do_io(response, command.all);

      rsp(response);
      rsp_shift(response, ir'length);
      rsp(response);
    end procedure;
    
    procedure blind_enumerate
    is
      variable command, response: byte_stream;
      constant all_ones : std_ulogic_vector(255 downto 0) := (others => '1');
      variable default_ir : std_ulogic_vector(255 downto 0);
      variable default_dr : std_ulogic_vector(255 downto 0);
      variable bypass_dr : std_ulogic_vector(255 downto 0);

      variable default_dr_point, tap_count: integer := 0;
      variable idcode : std_ulogic_vector(31 downto 0);
    begin
      command := null;

      write(command, cmd_run_x8(1));
      write(command, cmd_capture_dr);
      write(command, cmd_shift(all_ones, true));
      write(command, cmd_capture_ir);
      write(command, cmd_shift(all_ones, true));
      write(command, cmd_capture_dr);
      write(command, cmd_shift(all_ones, true));
      write(command, cmd_run(1));

      do_io(response, command.all);
      rsp(response);
      rsp(response);
      rsp_shift(response, default_dr);
      rsp(response);
      rsp_shift(response, default_ir);
      rsp(response);
      rsp_shift(response, bypass_dr);
      rsp(response);

      while bypass_dr(tap_count) = '0'
      loop
        if default_dr(default_dr_point) = '0' then
          log_info("Tap #"&to_string(tap_count)&": No IDCODE");
          default_dr_point := default_dr_point + 1;
        else
          idcode := default_dr(default_dr_point + 31 downto default_dr_point);
          log_info("Tap #"&to_string(tap_count)&": "&to_string(unsigned(idcode)));
          default_dr_point := default_dr_point + 32;
          assert_equal("Idcode", idcode, idcode_c, failure);
        end if;
        tap_count := tap_count + 1;
      end loop;

      assert_equal("Tap count", tap_count, 1, failure);
    end procedure;

    procedure shift_loopback_test(pad_count: integer; loopback_data: std_ulogic_vector := x"deadbeef")
    is
      variable response: byte_stream;
      constant pad_data: std_ulogic_vector(pad_count-1 downto 0) := (others => '0');
      variable rsp_data: std_ulogic_vector(pad_count + loopback_data'length - 1 downto 0);
    begin
      do_io(response, cmd_shift(pad_data & loopback_data, true));
      rsp_shift(response, rsp_data);

      assert_equal("Shift loopback", rsp_data(rsp_data'left downto pad_data'length), loopback_data, warning);
    end procedure;

    procedure ir_select
    is
      variable response: byte_stream;
    begin
      do_io(response, cmd_capture_ir);
      rsp(response);
    end procedure;

    procedure dr_select
    is
      variable response: byte_stream;
    begin
      do_io(response, cmd_capture_dr);
      rsp(response);
    end procedure;

    procedure loopback_div_delay_test(cd, rd: time; div: integer)
    is
    begin
      log_info("Shift loopback with delay = "&to_string(cd)&"/"&to_string(rd)&", div="&to_string(div));
      cmd_delay := cd;
      rsp_delay := rd;
      div_set(div);
      shift_loopback_test(1, x"ff12489c5a00");
    end procedure;
    
  begin
    done_s(0) <= '0';
    framed_queue_init(command_q);
    framed_queue_init(response_q);

    wait for 40 ns;

    chain_reset(3);
    blind_enumerate;
    ir_set(x"f");
    dr_select;

    loopback_div_delay_test(0 ns, 0 ns, 2);
    loopback_div_delay_test(3 ns, 5 ns, 3);
--    loopback_div_delay_test(3 ns, 5 ns, 2);

    wait for 50 us;

    log_info("JTAG test done");
    done_s(0) <= '1';
    wait;
  end process;

  -- ATE is the only block here with a clock
  ate: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;

    -- From host to routed endpoint and to ATE, as signals.
    signal ate_io_s : framed_io;
  begin
    master_q: process is
    begin
      ate_io_s.cmd.req <= framed_req_idle_c;
      wait for 40 ns;
      framed_queue_master_worker(ate_io_s.cmd.req, ate_io_s.cmd.ack, clock_s, command_q);
    end process;

    slave_q: process is
    begin
      ate_io_s.rsp.ack <= framed_ack_idle_c;
      wait for 40 ns;
      framed_queue_slave_worker(ate_io_s.rsp.req, ate_io_s.rsp.ack, clock_s, response_q);
    end process;

    reset_sync_clk: nsl_clocking.async.async_edge
      port map(
        data_i => async_reset_n_s,
        data_o => clock_reset_n_s,
        clock_i => clock_s
        );

    ate_impl: nsl_jtag.transactor.framed_ate
      port map(
        clock_i  => clock_s,
        reset_n_i => clock_reset_n_s,

        cmd_i => ate_io_s.cmd.req,
        cmd_o => ate_io_s.cmd.ack,
        rsp_o => ate_io_s.rsp.req,
        rsp_i => ate_io_s.rsp.ack,

        jtag_o => ate_o,
        jtag_i => ate_i
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 5 ns,
        reset_duration(0) => 5 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

  ate_i <= transport to_ate(tap_o) after cmd_delay;
  tap_i <= transport to_tap(ate_o) after rsp_delay;

  dut: block is
    signal tap_ir_s : std_ulogic_vector(3 downto 0);
    signal tap_reset_s, tap_run_s, tap_dr_capture_s,
      tap_dr_shift_s, tap_dr_update_s, tap_dr_in_s, tap_dr_out_s : std_ulogic;

    signal idcode_out_s, idcode_selected_s : std_ulogic;
    signal bypass_out_s, bypass_selected_s : std_ulogic;
  begin
    tap: nsl_jtag.tap.tap_port
      generic map(
        ir_len => 4
        )
      port map(
        jtag_i => tap_i,
        jtag_o => tap_o,

        default_instruction_i => "0010",

        ir_o => tap_ir_s,
        ir_out_i => "00",
        reset_o => tap_reset_s,
        run_o => tap_run_s,
        dr_capture_o => tap_dr_capture_s,
        dr_shift_o => tap_dr_shift_s,
        dr_update_o => tap_dr_update_s,
        dr_tdi_o => tap_dr_in_s,
        dr_tdo_i => tap_dr_out_s
        );

    idcode: nsl_jtag.tap.tap_dr
      generic map(
        ir_len => 4,
        dr_len => 32
        )
      port map(
        tck_i => tap_i.tck,
        tdi_i => tap_dr_in_s,
        tdo_o => idcode_out_s,

        match_ir_i => "0010",
        current_ir_i => tap_ir_s,
        active_o => idcode_selected_s,

        dr_capture_i => tap_dr_capture_s,
        dr_shift_i => tap_dr_shift_s,
        value_o => open,
        value_i => idcode_c
        );

    bypass: nsl_jtag.tap.tap_dr
      generic map(
        ir_len => 4,
        dr_len => 1
        )
      port map(
        tck_i => tap_i.tck,
        tdi_i => tap_dr_in_s,
        tdo_o => bypass_out_s,

        match_ir_i => "1111",
        current_ir_i => tap_ir_s,
        active_o => bypass_selected_s,

        dr_capture_i => tap_dr_capture_s,
        dr_shift_i => tap_dr_shift_s,
        value_o => open,
        value_i => "0"
        );

    tdo_gen: process(idcode_selected_s, idcode_out_s,
                     bypass_selected_s, bypass_out_s)
    begin
      tap_dr_out_s <= '-';

      if idcode_selected_s = '1' then
        tap_dr_out_s <= idcode_out_s;
      elsif bypass_selected_s = '1' then
        tap_dr_out_s <= bypass_out_s;
      end if;
    end process;
  end block;

end;
