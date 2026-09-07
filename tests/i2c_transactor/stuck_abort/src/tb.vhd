library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_bnoc, nsl_clocking, nsl_data, nsl_i2c, nsl_simulation;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

architecture arch of tb is

  signal clock_s : std_ulogic := '0';
  signal reset_n_clock_s, reset_n_async_s : std_ulogic;

  signal i2c_s : nsl_i2c.i2c.i2c_i;
  signal i2c_master_s, i2c_mem_s, i2c_stall_s : nsl_i2c.i2c.i2c_o;

  signal done_s : std_ulogic_vector(0 to 0);

  signal cmd_s, rsp_s : nsl_bnoc.framed.framed_bus;

  signal sync1_s : std_ulogic;

begin

  reset_sync: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_async_s,
      data_o => reset_n_clock_s,
      clock_i => clock_s
      );

  master: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => 10e6
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_clock_s,

      cmd_i => cmd_s.req,
      cmd_o => cmd_s.ack,
      rsp_o => rsp_s.req,
      rsp_i => rsp_s.ack,

      i2c_i => i2c_s,
      i2c_o => i2c_master_s
      );

  mem: nsl_i2c.clocked.clocked_memory
    generic map(
      address => "1010000",
      addr_width => 8
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_clock_s,

      i2c_i => i2c_s,
      i2c_o => i2c_mem_s
      );

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 3
      )
    port map(
      bus_i(0) => i2c_master_s,
      bus_i(1) => i2c_mem_s,
      bus_i(2) => i2c_stall_s,
      bus_o => i2c_s
      );

  -- Misbehaving device: after the first start condition, lets two SCL
  -- pulses through, then stretches the clock for longer than the
  -- master's stuck timeout before releasing the bus.
  stall: process
  begin
    i2c_stall_s.scl.drain_n <= '1';
    i2c_stall_s.sda.drain_n <= '1';

    wait until i2c_s.scl = '1' and i2c_s.sda = '0';
    wait until i2c_s.scl = '0';
    wait until i2c_s.scl = '1';
    wait until i2c_s.scl = '0';

    i2c_stall_s.scl.drain_n <= '0';
    wait for 50 us;
    i2c_stall_s.scl.drain_n <= '1';
    wait;
  end process;

  gen: process
  begin
    cmd_s.req.valid <= '0';

    wait for 1 us;

    -- Div 1, start, write one byte, stop. The stalling device blocks
    -- the write mid-byte; the write status must report failure and
    -- the stop must fail as bus ownership was lost, but a complete
    -- response frame must come back.
    framed_put(cmd_s.req, cmd_s.ack, clock_s, from_hex("0120405521"));

    -- Let the stalling device release the bus and the master see it
    -- idle again.
    wait until sync1_s = '1';
    wait for 150 us;

    -- Start, write memory device address, stop. Must complete
    -- normally now the bus recovered.
    framed_put(cmd_s.req, cmd_s.ack, clock_s, from_hex("2040a021"));
    wait;
  end process;

  chk: process
  begin
    done_s(0) <= '0';
    sync1_s <= '0';
    rsp_s.ack.ready <= '0';

    framed_check("stalled", rsp_s.req, rsp_s.ack, clock_s,
                 from_hex("000000ff"), LOG_LEVEL_FATAL);
    sync1_s <= '1';

    framed_check("recovered", rsp_s.req, rsp_s.ack, clock_s,
                 from_hex("000100"), LOG_LEVEL_FATAL);

    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => reset_n_async_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
