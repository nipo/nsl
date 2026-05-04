library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_bnoc, nsl_amba, nsl_data, nsl_simulation;
use nsl_bnoc.committed.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.axi_adapter.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
  constant valid_frame_count_c : natural := 35;
  constant error_frame_count_c : natural := 5;
  constant max_frame_size_c    : natural := 512;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  -- Selects committed source for committed_to_axi4_stream:
  -- '0' = axi4_stream_to_committed (round-trip test)
  -- '1' = committed_queue_master_worker (cancel test)
  signal phase_select_s : std_ulogic := '0';

  signal axi_in_s              : bus_t;
  signal axi_out_s             : bus_t;
  signal committed_from_axi_s  : committed_bus_t;
  signal committed_from_queue_s: committed_bus_t;
  signal committed_to_dut_s    : committed_bus_t;

  shared variable tx_axi_q       : nsl_amba.axi4_stream.frame_queue_root_t;
  shared variable rx_axi_q       : nsl_amba.axi4_stream.frame_queue_root_t;
  shared variable tx_committed_q : nsl_bnoc.testing.committed_queue_root;
begin

  -- Mux between the two committed sources
  committed_to_dut_s.req          <= committed_from_axi_s.req   when phase_select_s = '0'
                                     else committed_from_queue_s.req;
  committed_from_axi_s.ack.ready  <= committed_to_dut_s.ack.ready when phase_select_s = '0' else '0';
  committed_from_queue_s.ack.ready<= committed_to_dut_s.ack.ready when phase_select_s = '1' else '0';

  test: process
    variable prbs_state_v : nsl_data.prbs.prbs_state(14 downto 0) := (others => '1');
    variable size_seed1_v : positive := 42;
    variable size_seed2_v : positive := 123;
    variable rand_v       : real;
    variable size_v       : natural;
    variable data_v       : nsl_data.bytestream.byte_string(0 to max_frame_size_c - 1);
    variable check_status : boolean;
    variable probe_data_v : nsl_data.bytestream.byte_string(0 to 7)
                          := (x"de", x"ad", x"be", x"ef", x"ca", x"fe", x"ba", x"be");
  begin
    done_s <= (others => '0');

    nsl_amba.axi4_stream.frame_queue_init(tx_axi_q);
    nsl_amba.axi4_stream.frame_queue_init(rx_axi_q);
    nsl_bnoc.testing.committed_queue_init(tx_committed_q);

    wait for 10 us;

    -- Phase 1: full round-trip AXI -> committed -> AXI, tests both DUTs with valid frames
    for i in 0 to valid_frame_count_c - 1
    loop
      ieee.math_real.uniform(size_seed1_v, size_seed2_v, rand_v);
      size_v := 1 + natural(rand_v * real(max_frame_size_c - 1));

      data_v(0 to size_v - 1) := nsl_data.prbs.prbs_byte_string(prbs_state_v, nsl_data.prbs.prbs15, size_v);
      prbs_state_v := nsl_data.prbs.prbs_forward(prbs_state_v, nsl_data.prbs.prbs15, size_v * 8);

      log(LOG_LEVEL_INFO, "Sending valid frame #" & nsl_data.text.to_string(i) & ", size=" & nsl_data.text.to_string(size_v), LOG_COLOR_CYAN);
      nsl_amba.axi4_stream.frame_queue_check_io(
        root_master  => tx_axi_q,
        root_slave   => rx_axi_q,
        data1        => data_v(0 to size_v - 1),
        data2        => data_v(0 to size_v - 1),
        check_status => check_status,
        dt           => 10 ns,
        timeout      => 100 us,
        sev          => warning
        );
    end loop;
    done_s(0) <= '1';

    -- Phase 2: inject cancelled committed frames directly, bypassing axi4_stream_to_committed.
    -- A probe valid frame after all cancelled frames catches any leaked cancel frame
    -- (it would appear in rx_axi_q before the probe, causing a data mismatch).
    phase_select_s <= '1';

    for i in 0 to error_frame_count_c - 1 loop
      ieee.math_real.uniform(size_seed1_v, size_seed2_v, rand_v);
      size_v := 1 + natural(rand_v * real(max_frame_size_c - 1));

      data_v(0 to size_v - 1) := nsl_data.prbs.prbs_byte_string(prbs_state_v, nsl_data.prbs.prbs15, size_v);
      prbs_state_v := nsl_data.prbs.prbs_forward(prbs_state_v, nsl_data.prbs.prbs15, size_v * 8);

      log(LOG_LEVEL_INFO, "Sending cancelled frame #" & nsl_data.text.to_string(i)
          & ", size=" & nsl_data.text.to_string(size_v), LOG_COLOR_YELLOW);

      nsl_bnoc.testing.committed_queue_put(tx_committed_q, data_v(0 to size_v - 1), valid => false);
    end loop;

    log(LOG_LEVEL_INFO, "Sending probe frame after cancelled frames", LOG_COLOR_CYAN);
    nsl_bnoc.testing.committed_queue_put(tx_committed_q, probe_data_v, valid => true);
    nsl_amba.axi4_stream.frame_queue_check(rx_axi_q, probe_data_v,
                                           dt => 10 ns, timeout => 200 us, sev => warning);
    done_s(1) <= '1';

    wait;
  end process;

  tx_axi: process
  begin
    nsl_amba.axi4_stream.frame_queue_master(
      cfg      => axi4_stream_committed_config_c,
      root     => tx_axi_q,
      clock    => clock_s,
      stream_i => axi_in_s.s,
      stream_o => axi_in_s.m,
      dt       => 10 ns
      );
  end process;

  rx_axi: process
  begin
    nsl_amba.axi4_stream.frame_queue_slave(
      cfg      => axi4_stream_committed_config_c,
      root     => rx_axi_q,
      clock    => clock_s,
      stream_i => axi_out_s.m,
      stream_o => axi_out_s.s,
      dt       => 10 ns
      );
  end process;

  tx_committed: process
  begin
    nsl_bnoc.testing.committed_queue_master_worker(
      req   => committed_from_queue_s.req,
      ack   => committed_from_queue_s.ack,
      clock => clock_s,
      root  => tx_committed_q
      );
  end process;

  axi_to_committed: nsl_bnoc.axi_adapter.axi4_stream_to_committed
    port map(
      clock_i     => clock_s,
      reset_n_i   => reset_n_s,

      axi_i => axi_in_s.m,
      axi_o => axi_in_s.s,

      committed_o => committed_from_axi_s.req,
      committed_i => committed_from_axi_s.ack
      );

  committed_to_axi: nsl_bnoc.axi_adapter.committed_to_axi4_stream
    port map(
      clock_i     => clock_s,
      reset_n_i   => reset_n_s,

      committed_i => committed_to_dut_s.req,
      committed_o => committed_to_dut_s.ack,

      axi_o => axi_out_s.m,
      axi_i => axi_out_s.s
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count  => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration  => (others => 32 ns),
      clock_o(0)      => clock_s,
      reset_n_o(0)    => reset_n_s,
      done_i          => done_s
      );

end architecture;
