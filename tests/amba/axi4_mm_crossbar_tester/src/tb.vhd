library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_amba, nsl_data, nsl_xilinx, work;
use nsl_amba.axi4_mm.all;
use nsl_data.text.all;

-- A memory walker with transactions in flight, through the crossbar,
-- to a slave that takes addresses ahead.
entity xbench is
  generic(
    name_c: string;
    slice_c: boolean;
    tracker_c: boolean;
    backpressure_c: boolean;
    random_seed_c: positive
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o: out boolean;
    failures_o: out natural;
    write_cycles_o: out natural;
    read_cycles_o: out natural
    );
end entity;

architecture beh of xbench is

  constant tester_config_c: config_t := config(address_width => 32,
                                               data_bus_width => 64,
                                               id_width => 1,
                                               max_length => 16,
                                               size => true,
                                               burst => true);
  constant slave_config_c: config_t := config(address_width => 32,
                                              data_bus_width => 64,
                                              id_width => 2,
                                              max_length => 16,
                                              size => true,
                                              burst => true);
  constant routing_table_c: nsl_amba.address.address_vector
    := nsl_amba.address.routing_table(32, "x00000000/0");

  constant region_byte_l2_c: natural := 13;
  constant seed_c: natural := 5;

  signal m_s: master_vector(0 to 0);
  signal s_s: slave_vector(0 to 0);
  signal slave_m_s: master_vector(0 to 0);
  signal slave_s_s: slave_vector(0 to 0);
  signal mem_m_s: master_t;
  signal mem_s_s: slave_t;
  signal aw_valid_s, aw_ready_s, w_valid_s, w_ready_s: std_ulogic;
  signal start_s: std_ulogic := '0';
  signal busy_s, writing_s, done_s: std_ulogic;
  signal error_count_s: unsigned(31 downto 0);
  signal first_error_s: unsigned(31 downto 0);
  signal write_beats_s, write_bad_s, protocol_errors_s: natural;

begin

  tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => tester_config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => 16,
      seed_c => seed_c,
      outstanding_c => 8
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      start_i => start_s,
      axi_o => m_s(0),
      axi_i => s_s(0),
      busy_o => busy_s,
      writing_o => writing_s,
      done_o => done_s,
      error_count_o => error_count_s,
      first_error_address_o => first_error_s
      );

  crossbar: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => tester_config_c,
      slave_config_c => slave_config_c,
      master_count_c => 1,
      routing_table_c => routing_table_c,
      default_slave_c => 0,
      aw_tracking_depth_c => 8,
      max_outstanding_c => 8,
      master_slice_c => slice_c,
      slave_slice_c => slice_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      slave_i => m_s,
      slave_o => s_s,
      master_o => slave_m_s,
      master_i => slave_s_s
      );

  memory: entity work.slave_model
    generic map(
      config_c => slave_config_c,
      byte_size_l2_c => region_byte_l2_c,
      seed_c => seed_c,
      address_depth_c => 8,
      read_latency_c => 20,
      backpressure_c => backpressure_c,
      random_seed_c => random_seed_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      axi_i => mem_m_s,
      axi_o => mem_s_s,
      write_beats_o => write_beats_s,
      write_bad_o => write_bad_s,
      protocol_errors_o => protocol_errors_s
      );

  -- Optionally, the WID tracker the PS7 wrapper puts in front of its
  -- AXI3 slave ports.
  no_tracker: if not tracker_c
  generate
    aw_valid_s <= slave_m_s(0).aw.valid;
    aw_ready_s <= mem_s_s.aw.ready;
    w_valid_s <= slave_m_s(0).w.valid;
    w_ready_s <= mem_s_s.w.ready;
  end generate;

  with_tracker: if tracker_c
  generate
    tracker: nsl_xilinx.ps7.ps7_axi3_wid_tracker
      generic map(
        id_width_c => slave_config_c.id_width,
        depth_c => 8
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        aw_valid_i => slave_m_s(0).aw.valid,
        aw_id_i => std_ulogic_vector(slave_m_s(0).aw.id(slave_config_c.id_width-1 downto 0)),
        aw_valid_o => aw_valid_s,
        aw_ready_i => mem_s_s.aw.ready,
        aw_ready_o => aw_ready_s,
        w_valid_i => slave_m_s(0).w.valid,
        w_last_i => slave_m_s(0).w.last,
        w_valid_o => w_valid_s,
        w_ready_i => mem_s_s.w.ready,
        w_ready_o => w_ready_s,
        w_id_o => open
        );
  end generate;

  glue: process(slave_m_s, mem_s_s, aw_valid_s, aw_ready_s, w_valid_s, w_ready_s) is
    variable m: master_t;
    variable sl: slave_t;
  begin
    m := slave_m_s(0);
    m.aw.valid := aw_valid_s;
    m.w.valid := w_valid_s;
    mem_m_s <= m;
    sl := mem_s_s;
    sl.aw.ready := aw_ready_s;
    sl.w.ready := w_ready_s;
    slave_s_s(0) <= sl;
  end process;

  run: process is
    variable w, rd: natural := 0;
    variable failures: natural := 0;
  begin
    done_o <= false;
    failures_o <= 0;
    wait until reset_n_i = '1';
    wait until falling_edge(clock_i);
    start_s <= '1';
    loop
      wait until rising_edge(clock_i);
      exit when done_s = '1';
      if busy_s = '1' then
        if writing_s = '1' then
          w := w + 1;
        else
          rd := rd + 1;
        end if;
      end if;
    end loop;

    failures := to_integer(error_count_s) + write_bad_s + protocol_errors_s;
    report name_c & ": " & to_string(w) & " cycles writing, "
      & to_string(rd) & " cycles reading, "
      & to_string(failures) & " failures";
    write_cycles_o <= w;
    read_cycles_o <= rd;
    failures_o <= failures;
    done_o <= true;
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, work;

entity tb is
end entity;

architecture beh of tb is

  constant bench_count_c: natural := 5;
  constant beat_count_c: natural := 2 ** (13 - 3);

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

  direct_ready: entity work.xbench
    generic map(name_c => "no slices, always ready", slice_c => false, tracker_c => false,
                backpressure_c => false, random_seed_c => 1)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             done_o => done_s(0), failures_o => failures_s(0),
             write_cycles_o => write_cycles_s(0), read_cycles_o => read_cycles_s(0));

  sliced_ready: entity work.xbench
    generic map(name_c => "slices, always ready", slice_c => true, tracker_c => false,
                backpressure_c => false, random_seed_c => 2)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             done_o => done_s(1), failures_o => failures_s(1),
             write_cycles_o => write_cycles_s(1), read_cycles_o => read_cycles_s(1));

  sliced_stalling: entity work.xbench
    generic map(name_c => "slices, stalling", slice_c => true, tracker_c => false,
                backpressure_c => true, random_seed_c => 3)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             done_o => done_s(2), failures_o => failures_s(2),
             write_cycles_o => write_cycles_s(2), read_cycles_o => read_cycles_s(2));

  tracker_ready: entity work.xbench
    generic map(name_c => "slices, tracker, always ready", slice_c => true, tracker_c => true,
                backpressure_c => false, random_seed_c => 4)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             done_o => done_s(3), failures_o => failures_s(3),
             write_cycles_o => write_cycles_s(3), read_cycles_o => read_cycles_s(3));

  tracker_stalling: entity work.xbench
    generic map(name_c => "slices, tracker, stalling", slice_c => true, tracker_c => true,
                backpressure_c => true, random_seed_c => 5)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             done_o => done_s(4), failures_o => failures_s(4),
             write_cycles_o => write_cycles_s(4), read_cycles_o => read_cycles_s(4));

  watchdog: process is
  begin
    wait for 200 us;
    report "timeout" severity failure;
    wait;
  end process;

  stim: process is
    variable failures: natural := 0;
  begin
    for i in done_s'range
    loop
      if not done_s(i) then
        wait until done_s(i);
      end if;
      failures := failures + failures_s(i);
    end loop;
    wait until falling_edge(clock_s);

    stopped_s <= true;
    if failures = 0 then
      nsl_simulation.control.terminate(0);
    else
      nsl_simulation.control.terminate(1);
    end if;
    wait;
  end process;

end architecture;
