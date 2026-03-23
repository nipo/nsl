library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal framed_in_s, framed_out_s : bus_t;
  signal sized_s : bus_t;

  shared variable master_q, slave_q, check_q : frame_queue_root_t;

  constant cfg_c : config_t := config(1, last => true);
  constant pipe_cfg_c : config_t := config(1);

begin

  trx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee" & "111";
  begin
    done_s(0) <= '0';
    frame_queue_init(master_q);
    frame_queue_init(slave_q);
    frame_queue_init(check_q);

    wait for 40 ns;

    -- Test various frame sizes from 1 to 64 bytes
    for frame_size in 1 to 64
    loop
      frame_queue_put2(master_q, check_q,
                       data => prbs_byte_string(state_v, prbs31, frame_size));
      state_v := prbs_forward(state_v, prbs31, frame_size * 8);
    end loop;

    frame_queue_drain(cfg_c, master_q, timeout => 10 ms);
    wait for 100 us;

    frame_queue_assert_equal(cfg_c, slave_q, check_q);

    done_s(0) <= '1';
    wait;
  end process;

  master_proc: process is
  begin
    framed_in_s.m <= transfer_defaults(cfg_c);
    wait for 40 ns;
    frame_queue_master(cfg_c, master_q, clock_s, framed_in_s.s, framed_in_s.m);
  end process;

  slave_proc: process is
  begin
    framed_out_s.s <= accept(cfg_c, false);
    wait for 40 ns;
    frame_queue_slave(cfg_c, slave_q, clock_s, framed_out_s.m, framed_out_s.s);
  end process;

  -- Framed -> Sized converter
  from_framed: nsl_amba.stream_sized.axi4_stream_sized_from_framed
    generic map(
      in_config_c => cfg_c,
      out_config_c => cfg_c,
      max_txn_length_c => 128
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => framed_in_s.m,
      in_o => framed_in_s.s,

      out_o => sized_s.m,
      out_i => sized_s.s
      );

  -- Sized -> Framed converter
  to_framed: nsl_amba.stream_sized.axi4_stream_sized_to_framed
    generic map(
      in_config_c => cfg_c,
      out_config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      invalid_o => open,

      in_i => sized_s.m,
      in_o => sized_s.s,

      out_o => framed_out_s.m,
      out_i => framed_out_s.s
      );

  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "IN"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      bus_i => framed_in_s
      );

  dumper_pipe: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => pipe_cfg_c,
      prefix_c => "PIPE"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      bus_i => sized_s
      );

  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      bus_i => framed_out_s
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
