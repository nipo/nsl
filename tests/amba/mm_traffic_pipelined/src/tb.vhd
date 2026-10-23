library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_amba, nsl_data, work;
use nsl_amba.axi4_mm.all;
use nsl_data.text.all;

-- Runs the memory walker with several transactions in flight against
-- slaves that take addresses ahead, answer reads late and stall at
-- random, with and without a corrupted read beat, next to a run with a
-- single transaction in flight.
--
-- Against an always ready slave, a walker with enough transactions in
-- flight to cover the read latency must stream: writing and reading
-- the region each take about one cycle per beat.
entity tb is
end entity;

architecture beh of tb is

  constant config_c: config_t := config(address_width => 32,
                                        data_bus_width => 32,
                                        max_length => 256,
                                        size => true,
                                        burst => true);

  constant region_byte_l2_c: natural := 12;
  constant burst_length_c: positive := 8;
  constant beat_count_c: natural := 2 ** (region_byte_l2_c - config_c.data_bus_width_l2);
  -- Filling the hash pipe once per phase, the last write response
  -- and the read latency.
  constant stream_slack_c: natural := 32;

  constant bench_count_c: natural := 6;

  type natural_vector is array(natural range <>) of natural;
  type boolean_vector is array(natural range <>) of boolean;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal done_s: boolean_vector(0 to bench_count_c - 1);
  signal failures_s, write_cycles_s, read_cycles_s: natural_vector(0 to bench_count_c - 1);

begin

  clock_s <= (not clock_s) after 5 ns when not stopped_s else '0';
  reset_n_s <= '1' after 30 ns;

  serial_ready: entity work.bench
    generic map(
      name_c => "serial, always ready",
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => 31337,
      scramble_c => false,
      outstanding_c => 1,
      address_depth_c => 4,
      read_latency_c => 4,
      backpressure_c => false,
      random_seed_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0),
      failures_o => failures_s(0),
      write_cycles_o => write_cycles_s(0),
      read_cycles_o => read_cycles_s(0)
      );

  pipelined_ready: entity work.bench
    generic map(
      name_c => "4 outstanding, always ready",
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => 31337,
      scramble_c => false,
      outstanding_c => 4,
      address_depth_c => 4,
      read_latency_c => 4,
      backpressure_c => false,
      random_seed_c => 2
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1),
      failures_o => failures_s(1),
      write_cycles_o => write_cycles_s(1),
      read_cycles_o => read_cycles_s(1)
      );

  pipelined_stalling: entity work.bench
    generic map(
      name_c => "4 outstanding, stalling, 2 addresses ahead",
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => 1234,
      scramble_c => false,
      outstanding_c => 4,
      address_depth_c => 2,
      read_latency_c => 9,
      backpressure_c => true,
      random_seed_c => 3
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2),
      failures_o => failures_s(2),
      write_cycles_o => write_cycles_s(2),
      read_cycles_o => read_cycles_s(2)
      );

  pipelined_scrambled: entity work.bench
    generic map(
      name_c => "3 outstanding, stalling, scrambled",
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => 42,
      scramble_c => true,
      outstanding_c => 3,
      address_depth_c => 8,
      read_latency_c => 1,
      backpressure_c => true,
      random_seed_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(3),
      failures_o => failures_s(3),
      write_cycles_o => write_cycles_s(3),
      read_cycles_o => read_cycles_s(3)
      );

  pipelined_corrupt: entity work.bench
    generic map(
      name_c => "4 outstanding, stalling, corrupted beat",
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => 31337,
      scramble_c => false,
      outstanding_c => 4,
      address_depth_c => 4,
      read_latency_c => 5,
      backpressure_c => true,
      random_seed_c => 5,
      corrupt_address_c => 16#2a4#
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(4),
      failures_o => failures_s(4),
      write_cycles_o => write_cycles_s(4),
      read_cycles_o => read_cycles_s(4)
      );

  serial_corrupt: entity work.bench
    generic map(
      name_c => "serial, stalling, corrupted beat",
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => 31337,
      scramble_c => false,
      outstanding_c => 1,
      address_depth_c => 4,
      read_latency_c => 5,
      backpressure_c => true,
      random_seed_c => 6,
      corrupt_address_c => 16#ffc#
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(5),
      failures_o => failures_s(5),
      write_cycles_o => write_cycles_s(5),
      read_cycles_o => read_cycles_s(5)
      );

  watchdog: process is
  begin
    wait for 10 ms;
    assert stopped_s
      report "watchdog fired, a walker is stuck"
      severity failure;
    wait;
  end process;

  stim: process is
    variable failures: natural := 0;
  begin
    wait until reset_n_s = '1';

    for i in done_s'range
    loop
      if not done_s(i) then
        wait until done_s(i);
      end if;
    end loop;
    wait until falling_edge(clock_s);

    for i in failures_s'range
    loop
      failures := failures + failures_s(i);
    end loop;

    if write_cycles_s(1) > beat_count_c + stream_slack_c
      or read_cycles_s(1) > beat_count_c + stream_slack_c then
      failures := failures + 1;
      report "pipelined walker does not stream: "
        & to_string(write_cycles_s(1)) & " cycles writing and "
        & to_string(read_cycles_s(1)) & " cycles reading "
        & to_string(beat_count_c) & " beats"
        severity error;
    end if;

    stopped_s <= true;
    if failures = 0 then
      nsl_simulation.control.terminate(0);
    else
      nsl_simulation.control.terminate(1);
    end if;
    wait;
  end process;

end architecture;
