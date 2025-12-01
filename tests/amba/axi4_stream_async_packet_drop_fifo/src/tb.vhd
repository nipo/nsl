library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;

entity tb is
end tb;

architecture arch of tb is

  constant nbr_scenario : integer := 3;
  constant config_c : stream_cfg_array_t :=
    (0 => config(1, last => true),
     1 => config(2, last => true),
     2 => config(4, last => true));

  constant word_count_l2_c : integer := 9;
  constant word_count_c : integer := 2**word_count_l2_c;

  signal in_clock_s, in_reset_n_s : std_ulogic;
  signal out_clock_s, out_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario - 1);

begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate
    signal input_s, output_s, out_paced_s: bus_t;
    signal overrun_s : std_ulogic;
    shared variable master_q, slave_q, check_q : frame_queue_root_t;
    shared variable pkt_send_cnt_v : integer := 0;
    shared variable index_v, nbr_dropped_pkts_v, nbr_of_pkts_v : integer := 0;
    signal phase_s : std_ulogic;
    constant nbr_beat_to_play : integer := 128;
  begin
  gen_frm_proc: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;

    variable frm, frm_clone : frame_t;
  begin
    done_s(i) <= '0';
    phase_s <= '0';
    frame_queue_init(master_q);
    frame_queue_init(slave_q);
    frame_queue_init(check_q);

    wait for 200 ns;

    log_info("INFO: Scenario : " & to_string(i) & " Normal FIFO test, no overrun.");
    for stream_beat_count in 1 to nbr_beat_to_play/config_c(i).data_width
    loop
      frame_byte_count := stream_beat_count * config_c(i).data_width;

      frame_queue_check_io(root_master => master_q, 
                           root_slave  => slave_q, 
                           data => prbs_byte_string(state_v, prbs31, frame_byte_count),
                           timeout => 100000 us);

      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
      nbr_of_pkts_v := nbr_of_pkts_v + 1;
    end loop;

    phase_s <= '1';

    wait for 100 ns;

    log_info("INFO:  Scenario : " & to_string(i) &  " speed test, fifo shoudl overrun.");
    for stream_beat_count in 1 to 200
    loop
      frame_byte_count := word_count_c/config_c(i).data_width - config_c(i).data_width;

      frm := frame(prbs_byte_string(state_v, prbs31, frame_byte_count));
      frame_queue_put2(master_q, check_q, frm);
      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);

      nbr_of_pkts_v := nbr_of_pkts_v + 1;
    end loop;

    frame_queue_drain(config_c(i), master_q, timeout => 100000 us);
    wait for 10000 ns;
    get_queue_size("Slave", slave_q); 
    get_queue_size("Check", check_q);
    log_info("INFO: Asser queue equal scenario : " & to_string(i));
    frame_queue_assert_equal(cfg => config_c(i),
                             a => slave_q,
                             b => check_q,
                             sev => failure);

    log_info("INFO:  Scenario : " & to_string(i) & " Number of played packets " & to_string(nbr_of_pkts_v));
    log_info("INFO:  Scenario : " & to_string(i) &  " Number of dropped packets " & to_string(nbr_dropped_pkts_v));

    done_s(i) <= '1';
    wait;
  end process;

  master_proc: process is
  begin
    input_s.m <= transfer_defaults(config_c(i));
    wait for 40 ns;
    frame_queue_master(config_c(i), master_q, in_clock_s, input_s.s, input_s.m, timeout => 1000 us);
  end process;

  overrun_proc: process is
    variable trashed_frm_v : frame_t;
  begin
    wait until rising_edge(out_clock_s);
    wait until is_last(config_c(i), input_s.m) and is_valid(config_c(i), input_s.m);
    if phase_s = '1' then
      if overrun_s = '1' then
        nbr_dropped_pkts_v := nbr_dropped_pkts_v + 1;
        frame_queue_delete(check_q, trashed_frm_v, index_v);
        if index_v > 0 then
          index_v := index_v - 1; -- we remove an element 
        end if;
      end if;
      index_v := index_v + 1;
    end if;
  end process;

  slave_proc: process is
  begin
    output_s.s <= accept(config_c(i), false);
    wait for 40 ns;
    frame_queue_slave(config_c(i), slave_q, out_clock_s, output_s.m, output_s.s);
  end process;

  -- dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
  --   generic map(
  --     config_c => config_c(i),
  --     prefix_c => "IN"
  --     )
  --   port map(
  --     clock_i => in_clock_s,
  --     reset_n_i => in_reset_n_s,

  --     bus_i => input_s
  --     );

  -- dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
  --   generic map(
  --     config_c => config_c(i),
  --     prefix_c => "OUT"
  --     )
  --   port map(
  --     clock_i => out_clock_s,
  --     reset_n_i => out_reset_n_s,

  --     bus_i => output_s
  --     );
  
  dut: nsl_amba.stream_fifo.axi4_stream_async_packet_drop_fifo
    generic map(
      config_c => config_c(i),
      word_count_l2_c => word_count_l2_c,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => in_clock_s,
      clock_i(1) => out_clock_s,
      reset_n_i => in_reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => output_s.m,
      out_i => output_s.s,

      overrun_o => overrun_s
      );
  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 2,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 5 ns,
      clock_period(1) => 10 ns,
      reset_duration => (others => 100 ns),
      clock_o(0) => in_clock_s,
      clock_o(1) => out_clock_s,
      reset_n_o(0) => in_reset_n_s,
      reset_n_o(1) => out_reset_n_s,
      done_i => done_s
      );
end;
