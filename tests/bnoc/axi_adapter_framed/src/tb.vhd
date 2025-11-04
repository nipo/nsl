library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_amba, nsl_data, nsl_simulation;
use nsl_bnoc.framed.all;
use nsl_bnoc.axi_adapter.all;
use nsl_bnoc.testing.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal framed_in_s, framed_out_s: framed_bus_t;
  signal axi_s : bus_t;

  shared variable framed_send_q, framed_recv_q, framed_check_q: framed_queue_root;

begin

  test: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;
    variable frame_data : byte_string(0 to 63);
    variable rx_data, expected_data : byte_stream;
  begin
    done_s(0) <= '0';
    framed_queue_init(framed_send_q);
    framed_queue_init(framed_recv_q);
    framed_queue_init(framed_check_q);

    wait for 40 ns;

    -- Test various frame sizes
    for frame_count in 1 to 16
    loop
      frame_byte_count := frame_count * 4;
      frame_data(0 to frame_byte_count-1) := prbs_byte_string(state_v, prbs31, frame_byte_count);
      framed_queue_put(framed_send_q, frame_data(0 to frame_byte_count-1));
      framed_queue_put(framed_check_q, frame_data(0 to frame_byte_count-1));
      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
    end loop;

    wait for 50 us;

    -- Check all received frames match expected
    for frame_count in 1 to 16
    loop
      framed_queue_get(framed_recv_q, rx_data);
      framed_queue_get(framed_check_q, expected_data);
      framed_assert("Framed", rx_data.all, expected_data.all);
      deallocate(rx_data);
      deallocate(expected_data);
    end loop;

    log_info("Framed adapter test passed");
    done_s(0) <= '1';
    wait;
  end process;

  master: process is
  begin
    framed_in_s.req <= framed_req_idle_c;
    wait for 40 ns;
    framed_queue_master_worker(framed_in_s.req, framed_in_s.ack, clock_s, framed_send_q);
  end process;

  slave: process is
  begin
    framed_out_s.ack <= framed_ack_idle_c;
    wait for 40 ns;
    framed_queue_slave_worker(framed_out_s.req, framed_out_s.ack, clock_s, framed_recv_q);
  end process;

  framed_to_axi: nsl_bnoc.axi_adapter.framed_to_axi4_stream
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      framed_i => framed_in_s.req,
      framed_o => framed_in_s.ack,

      axi_o => axi_s.m,
      axi_i => axi_s.s
      );

  axi_to_framed: nsl_bnoc.axi_adapter.axi4_stream_to_framed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      framed_o => framed_out_s.req,
      framed_i => framed_out_s.ack
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
