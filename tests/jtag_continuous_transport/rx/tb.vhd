library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation, nsl_data;
use nsl_jtag.jtag.all;
use nsl_jtag.transactor.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

-- Integration test, RX direction: the ATE (framed transactor) drives a real
-- simulation TAP, and a continuous_transport_slave terminates the protocol
-- against a custom register. One batch carries preamble + SOF + a data frame
-- holding a payload on TDI; the test checks the payload reaches the slave's
-- system-side rx_o, exercising the whole TDI -> deserializer -> deframer ->
-- RX FIFO path through the actual jtag_tap_register binding.
entity tb is
end entity;

architecture arch of tb is

  constant idcode_c : std_ulogic_vector(31 downto 0) := x"87654321";
  constant idcode_instruction_c : std_ulogic_vector(3 downto 0) := x"2";
  constant user0_instruction_c : std_ulogic_vector(3 downto 0) := x"8";

  constant payload_c : byte_string := from_hex("deadbeef");

  signal done_s : std_ulogic_vector(0 to 0);
  signal rx_done : std_ulogic := '0';

  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  shared variable command_q, response_q : framed_queue_root;

  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  -- System-side received stream from the slave.
  signal rx_req : nsl_bnoc.framed.framed_req_t;
  signal rx_ack : nsl_bnoc.framed.framed_ack_t;

begin

  host: process
    procedure do_io(response : out byte_stream; command : in byte_string) is
      variable rsp : byte_stream;
    begin
      framed_queue_put(command_q, command);
      framed_queue_get(response_q, rsp);
      response := rsp;
    end procedure;

    procedure chain_reset(div : integer range 1 to 256) is
      variable response : byte_stream;
    begin
      do_io(response, cmd_reset(5) & cmd_divisor(div) & cmd_reset(5) & cmd_run(1));
    end procedure;

    procedure ir_set(ir : std_ulogic_vector) is
      variable command, response : byte_stream;
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

    -- One continuous-transport batch carrying the given payload on TDI.
    procedure send_batch(payload : byte_string) is
      variable command, response : byte_stream;
      constant preamble : byte_string := (x"55", x"55");
      constant sof : byte_string := (0 => x"d5");
      constant pad : byte_string := (x"f0", x"f0", x"f0", x"f0");
      variable header : byte;
      variable batch : byte_stream := null;
      variable tdo : byte_string(0 to 2 + 1 + 1 + payload'length + 4 - 1);
    begin
      -- Data frame header: control=0, last=1, length-1.
      header := "0" & "1" & std_ulogic_vector(to_unsigned(payload'length - 1, 6));

      write(batch, preamble);
      write(batch, sof);
      write(batch, header);
      write(batch, payload);
      write(batch, pad);

      command := null;
      write(command, cmd_capture_dr);
      write(command, cmd_shift_bytes(batch.all, true));
      write(command, cmd_run(1));
      do_io(response, command.all);
      rsp(response);
      rsp_shift_bytes(response, tdo);
      rsp(response);
    end procedure;

  begin
    done_s(0) <= '0';
    framed_queue_init(command_q);
    framed_queue_init(response_q);

    wait for 40 ns;

    chain_reset(3);
    ir_set(user0_instruction_c);

    send_batch(payload_c);

    wait until rx_done = '1' for 200 us;
    assert rx_done = '1'
      report "payload never reached the slave RX side" severity failure;

    log_info("continuous_transport RX integration OK");
    done_s(0) <= '1';
    wait;
  end process;

  ate: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;
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
        clock_i => clock_s,
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

  ate_i <= transport to_ate(tap_o);
  tap_i <= transport to_tap(ate_o);

  dut: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;
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

    slave: nsl_jtag.continuous_transport.continuous_transport_slave
      generic map(
        reg_id_c => 1,
        rx_fifo_depth_c => 256,
        tx_fifo_depth_c => 256,
        preamble_count_c => 2
        )
      port map(
        clock_i => clock_s,
        reset_n_i => clock_reset_n_s,
        reset_n_o => open,
        tx_i => framed_req_idle_c,
        tx_o => open,
        rx_o => rx_req,
        rx_i => rx_ack
        );

    rx_ack.ready <= '1';

    -- Collect rx_o and check it against the payload.
    monitor: process(clock_s)
      variable idx : integer := 0;
    begin
      if rising_edge(clock_s) then
        if rx_req.valid = '1' and rx_ack.ready = '1' then
          assert_equal("rx", "byte", rx_req.data, payload_c(payload_c'left + idx), failure);
          if idx = payload_c'length - 1 then
            assert rx_req.last = '1' report "missing last on final RX byte" severity failure;
            rx_done <= '1';
          else
            assert rx_req.last = '0' report "early last on RX byte" severity failure;
          end if;
          idx := idx + 1;
        end if;
      end if;
    end process;

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

end architecture;
