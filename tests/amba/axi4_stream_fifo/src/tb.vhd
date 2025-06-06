library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal in_clock_s, in_reset_n_s : std_ulogic;
  signal out_clock_s, out_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal input_s, output_s: bus_t;
  shared variable master_q, slave_q, check_q: frame_queue_root_t;

  constant cfg_c: config_t := config(12, last => true);

begin

  trx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;
  begin
    done_s(0) <= '0';
    frame_queue_init(master_q);
    frame_queue_init(slave_q);
    frame_queue_init(check_q);

    wait for 40 ns;

    for stream_beat_count in 1 to 16
    loop
      frame_byte_count := stream_beat_count * cfg_c.data_width;

      frame_queue_put2(master_q, check_q, prbs_byte_string(state_v, prbs31, frame_byte_count));
      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
    end loop;

    frame_queue_drain(cfg_c, master_q, timeout => 1 ms);
    wait for 10 us;

    frame_queue_assert_equal(cfg_c, slave_q, check_q);

    done_s(0) <= '1';
    wait;
  end process;

  master_proc: process is
  begin
    input_s.m <= transfer_defaults(cfg_c);
    wait for 40 ns;
    frame_queue_master(cfg_c, master_q, in_clock_s, input_s.s, input_s.m);
  end process;

  slave_proc: process is
  begin
    output_s.s <= accept(cfg_c, false);
    wait for 40 ns;
    frame_queue_slave(cfg_c, slave_q, out_clock_s, output_s.m, output_s.s);
  end process;

  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "IN"
      )
    port map(
      clock_i => in_clock_s,
      reset_n_i => in_reset_n_s,

      bus_i => input_s
      );

  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => out_clock_s,
      reset_n_i => out_reset_n_s,

      bus_i => output_s
      );
  
  dut: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      depth_c => 16,
      config_c => cfg_c,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => in_clock_s,
      clock_i(1) => out_clock_s,
      reset_n_i => in_reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => output_s.m,
      out_i => output_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 7 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => in_clock_s,
      clock_o(1) => out_clock_s,
      reset_n_o(0) => in_reset_n_s,
      done_i => done_s
      );
  
end;
