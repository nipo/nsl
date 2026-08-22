library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation, nsl_data;
use nsl_jtag.jtag.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

-- Full-hardware loopback: a continuous_transport_master drives a framed_ate
-- against a simulation TAP terminated by a continuous_transport_slave. Packets
-- are pushed into both TX sides and checked on the opposite RX sides,
-- covering the whole path in both directions: master framer -> command frames
-- -> ATE -> TDI -> slave, and slave framer -> TDO -> response frames ->
-- deserializer -> master. The second round uses packets larger than one
-- chunk, exercising multi-chunk packets, budget growth from tx-level
-- advertisements, and multi-batch transfers.
entity tb is
end entity;

architecture arch of tb is

  constant idcode_c : std_ulogic_vector(31 downto 0) := x"87654321";
  constant idcode_instruction_c : std_ulogic_vector(3 downto 0) := x"2";
  constant user0_instruction_c : std_ulogic_vector(3 downto 0) := x"8";

  function seq(base : integer; len : integer) return byte_string is
    variable ret : byte_string(0 to len-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_byte((base + i * 7) mod 256);
    end loop;
    return ret;
  end function;

  signal done_s : std_ulogic_vector(0 to 0);

  shared variable mtx_q, mrx_q, stx_q, srx_q : framed_queue_root;

  signal clock_s : std_ulogic := '0';
  signal clock_reset_n_s : std_ulogic;
  signal async_reset_n_s : std_ulogic;

  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  signal cmd_bus, rsp_bus, mtx_bus, mrx_bus, stx_bus, srx_bus :
    nsl_bnoc.framed.framed_bus;

  signal slave_reset_n_s : std_ulogic;

begin

  host: process
    variable got : byte_stream;
  begin
    done_s(0) <= '0';
    framed_queue_init(mtx_q);
    framed_queue_init(mrx_q);
    framed_queue_init(stx_q);
    framed_queue_init(srx_q);

    wait for 40 ns;

    -- Master TX may be queued from the start: the master buffers it and the
    -- first batch's Test-Logic-Reset happens before any payload flows.
    framed_queue_put(mtx_q, seq(16#10#, 5));

    -- Slave TX must wait for the first batch's TLR, which flushes the slave
    -- transport.
    wait until slave_reset_n_s = '0';
    wait until slave_reset_n_s = '1';
    framed_queue_put(stx_q, seq(16#80#, 3));

    framed_queue_get(srx_q, got);
    assert_equal("master->slave short", got.all, seq(16#10#, 5), failure);
    framed_queue_get(mrx_q, got);
    assert_equal("slave->master short", got.all, seq(16#80#, 3), failure);

    -- Larger than one chunk in both directions, concurrently.
    framed_queue_put(mtx_q, seq(16#20#, 100));
    framed_queue_put(stx_q, seq(16#90#, 64));

    framed_queue_get(srx_q, got);
    assert_equal("master->slave long", got.all, seq(16#20#, 100), failure);
    framed_queue_get(mrx_q, got);
    assert_equal("slave->master long", got.all, seq(16#90#, 64), failure);

    log_info("continuous_transport master loopback OK");
    done_s(0) <= '1';
    wait;
  end process;

  -- Payload sources and sinks.
  mtx_worker: process is
  begin
    mtx_bus.req <= framed_req_idle_c;
    wait for 40 ns;
    framed_queue_master_worker(mtx_bus.req, mtx_bus.ack, clock_s, mtx_q);
  end process;

  mrx_worker: process is
  begin
    mrx_bus.ack <= framed_ack_idle_c;
    wait for 40 ns;
    framed_queue_slave_worker(mrx_bus.req, mrx_bus.ack, clock_s, mrx_q);
  end process;

  stx_worker: process is
  begin
    stx_bus.req <= framed_req_idle_c;
    wait for 40 ns;
    framed_queue_master_worker(stx_bus.req, stx_bus.ack, clock_s, stx_q);
  end process;

  srx_worker: process is
  begin
    srx_bus.ack <= framed_ack_idle_c;
    wait for 40 ns;
    framed_queue_slave_worker(srx_bus.req, srx_bus.ack, clock_s, srx_q);
  end process;

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => async_reset_n_s,
      data_o => clock_reset_n_s,
      clock_i => clock_s
      );

  master: nsl_jtag.continuous_transport.continuous_transport_master
    generic map(
      ir_len_max_c => 4,
      batch_bytes_max_c => 512,
      divisor_m1_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => clock_reset_n_s,

      enable_i => '1',
      poll_backoff_i => to_unsigned(100, 16),

      ir_i => user0_instruction_c,
      ir_len_m1_i => 3,

      cmd_o => cmd_bus.req,
      cmd_i => cmd_bus.ack,
      rsp_i => rsp_bus.req,
      rsp_o => rsp_bus.ack,

      tx_i => mtx_bus.req,
      tx_o => mtx_bus.ack,
      rx_o => mrx_bus.req,
      rx_i => mrx_bus.ack,
      rx_room_i => to_unsigned(512, 16)
      );

  ate_impl: nsl_jtag.transactor.framed_ate
    port map(
      clock_i => clock_s,
      reset_n_i => clock_reset_n_s,
      cmd_i => cmd_bus.req,
      cmd_o => cmd_bus.ack,
      rsp_o => rsp_bus.req,
      rsp_i => rsp_bus.ack,
      jtag_o => ate_o,
      jtag_i => ate_i
      );

  ate_i <= transport to_ate(tap_o);
  tap_i <= transport to_tap(ate_o);

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
      reset_n_o => slave_reset_n_s,
      tx_i => stx_bus.req,
      tx_o => stx_bus.ack,
      rx_o => srx_bus.req,
      rx_i => srx_bus.ack
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

end architecture;
