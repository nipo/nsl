library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation, nsl_data, nsl_math, nsl_bnoc;
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
  constant idcode_instruction_c : std_ulogic_vector(3 downto 0) := x"2";
  constant user0_instruction_c : std_ulogic_vector(3 downto 0) := x"8";
  
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
      variable rsp: byte_stream;
    begin
      log_info("< " & to_string(command));
      framed_queue_put(command_q, command);
      framed_queue_get(response_q, rsp);
      log_info("> " & to_string(rsp.all));
      response := rsp;
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

    procedure jtag_fifo_exchange(data_i: in byte;
                           valid_i: in boolean;
                           last_i: in boolean;
                           ready_o: out boolean;

                           data_o: out byte;
                           valid_o: out boolean;
                           last_o: out boolean;
                           ready_i: in boolean)
    is
      variable command, response: byte_stream;
      variable tx_reg, rx_reg: std_ulogic_vector(10 downto 0);
    begin
      command := null;

      if ready_i then
        tx_reg(10) := '1';
      else
        tx_reg(10) := '0';
      end if;
      if valid_i then
        tx_reg(9) := '1';
      else
        tx_reg(9) := '0';
      end if;
      if last_i then
        tx_reg(8) := '1';
      else
        tx_reg(8) := '0';
      end if;
      tx_reg(7 downto 0) := data_i;
      
      write(command, cmd_capture_dr);
      write(command, cmd_shift(tx_reg, true));
      write(command, cmd_run(1));

      do_io(response, command.all);
      rsp(response);
      rsp_shift(response, rx_reg);
      rsp(response);

      data_o := rx_reg(7 downto 0);
      last_o := rx_reg(8) = '1';
      valid_o := rx_reg(9) = '1';
      ready_o := rx_reg(10) = '1';
    end procedure;

    procedure fifo_loopback_test(payload: byte_string)
    is
      alias tx_data: byte_string(0 to payload'length-1) is payload;
      variable rx_data: byte_stream := null;
      variable rx_valid, rx_ready, rx_last, tx_valid, tx_ready, tx_last: boolean;
      variable rx_complete: boolean := false;
      variable tx_byte, rx_byte: byte;
      variable tx_point: integer := 0;
    begin
      while not rx_complete
      loop
        if tx_point < tx_data'length then
          tx_byte := tx_data(tx_point);
          tx_valid := true;
          tx_last := tx_point = tx_data'length - 1;
        else
          tx_byte := x"00";
          tx_valid := false;
          tx_last := false;
        end if;
        rx_ready := not rx_complete;

        jtag_fifo_exchange(tx_byte, tx_valid, tx_last, tx_ready,
                           rx_byte, rx_valid, rx_last, rx_ready);

        if tx_valid and tx_ready then
          tx_point := tx_point + 1;
        end if;

        if rx_valid and rx_ready then
          write(rx_data, rx_byte);
          rx_complete := rx_last;
        end if;
      end loop;

      assert_equal("fifo_loopback_test", rx_data.all, tx_data, FAILURE);
    end procedure;
    
    variable rd: byte;
    variable rv,rl,tr: boolean;
    
  begin
    done_s(0) <= '0';
    framed_queue_init(command_q);
    framed_queue_init(response_q);

    wait for 40 ns;

    chain_reset(3);
    blind_enumerate;
    ir_set(x"f");
    dr_select;
    ir_set(user0_instruction_c);

    fifo_loopback_test(from_hex("deadbeefdecafbad0123456789abcdef"));
    fifo_loopback_test(from_hex("0123456789abcdefdeadbeefdecafbad"));

    
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
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s, reset_n_s : std_ulogic;
    
    signal io_s: framed_io;
  begin
    reset_sync_clk: nsl_clocking.async.async_edge
      port map(
        data_i => async_reset_n_s,
        data_o => clock_reset_n_s,
        clock_i => clock_s
        );

    tap: nsl_simulation.jtag.jtag_sim_tap
      generic map(
        idcode_c => idcode_c,
        idcode_instruction_c => idcode_instruction_c,
        user0_instruction_c => user0_instruction_c
        )
      port map(
        tck_i => tap_i.tck,
        tms_i => tap_i.tms,
        tdi_i => tap_i.tdi,
        tdo_o => tap_o.tdo.v
        );
    tap_o.tdo.en <= '1';

    jtag_io: nsl_jtag.fifo_transport.jtag_fifo_transport_slave
      generic map(
        data_reg_no_c => 1,
        status_reg_no_c => 2,
        rx_fifo_depth_c => 256,
        tx_fifo_depth_c => 256,
        width_c => 9
        )
      port map(
        clock_i => clock_s,
        reset_n_i => clock_reset_n_s,
        reset_n_o => reset_n_s,

        tx_data_i(8) => io_s.rsp.req.last,
        tx_data_i(7 downto 0) => io_s.rsp.req.data,
        tx_valid_i => io_s.rsp.req.valid,
        tx_ready_o => io_s.rsp.ack.ready,

        rx_data_o(8) => io_s.cmd.req.last,
        rx_data_o(7 downto 0) => io_s.cmd.req.data,
        rx_valid_o => io_s.cmd.req.valid,
        rx_ready_i => io_s.cmd.ack.ready
        );

    loopback_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 256,
        clk_count => 1
        )
      port map(
        p_resetn => reset_n_s,
        p_clk(0) => clock_s,

        p_in_val => io_s.cmd.req,
        p_in_ack => io_s.cmd.ack,
        p_out_val => io_s.rsp.req,
        p_out_ack => io_s.rsp.ack
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

end;
