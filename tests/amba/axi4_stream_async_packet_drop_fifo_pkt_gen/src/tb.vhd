library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;
use nsl_logic.bool.all;

entity tb is
end tb;

architecture arch of tb is

  constant nbr_scenario_c : integer := 1;
  constant word_count_l2_c : integer := 9;
  constant word_count_c : integer := 2**word_count_l2_c;
  constant mtu_c : integer := word_count_c;
  constant pkt_to_play_c : integer := 200;
  constant max_error_in_a_row_c : integer := 100;
  constant igp_c : integer := 0;
  constant cmd_config_c : config_t := config(4, last => true);
  constant config_c : stream_cfg_array_t :=
    (0 => config(1, keep => true, last => true),
     1 => config(2, keep => true, last => true),
     2 => config(4, keep => true, last => true));

  signal in_clock_s, in_reset_n_s : std_ulogic;
  signal out_clock_s, out_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario_c - 1) := (others => '0');

begin

  gen_scenarios : for i in 0 to nbr_scenario_c-1 generate
    signal overrun_s, enable_s : std_ulogic;
    signal nbr_dropped_pkts_v, nbr_header_seqnum_error_detected_v, nbr_pkts_played_v, max_drop_pkt_row_v, nbr_pkt_out_v : integer := 0;
    signal drop_pkt_proportion : real := 0.0;
    signal input_s, output_s,output_paced_s, cmd_bus, stats_bus : bus_t;
  begin

    cmd_gen : nsl_amba.stream_traffic.random_cmd_generator
    generic map (
      mtu_c => mtu_c,
      cmd_config_c => cmd_config_c,
      min_pkt_size_c => 2
      )
    port map (
      clock_i => in_clock_s,
      reset_n_i => in_reset_n_s,

      enable_i => enable_s,

      cmd_o => cmd_bus.m,
      cmd_i => cmd_bus.s
      );
    
    enable_s <= to_logic(nbr_pkts_played_v < pkt_to_play_c);

    pkt_gen : nsl_amba.stream_traffic.random_pkt_generator
      generic map (
        mtu_c => mtu_c,
        cmd_config_c => cmd_config_c,
        packet_config_c => config_c(i),
        igp_c => igp_c
        )
      port map (
        clock_i => in_clock_s,
        reset_n_i => in_reset_n_s,

        cmd_i => cmd_bus.m,
        cmd_o => cmd_bus.s,

        packet_o => input_s.m,
        packet_i => input_s.s
        );

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

    pkt_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
    generic map(
        config_c               => config_c(i),
        probability_denom_l2_c => 30,
        probability_c          => 0.8
    )
    port map(
        reset_n_i => in_reset_n_s,
        clock_i   => out_clock_s,

        in_i => output_s.m,
        in_o => output_s.s,

        out_o => output_paced_s.m,
        out_i => output_paced_s.s
    );
    
    pkt_checker : nsl_amba.stream_traffic.random_pkt_validator
    generic map (
      mtu_c => mtu_c,
      packet_config_c => config_c(i)
      )
    port map (
      clock_i => out_clock_s,
      reset_n_i => in_reset_n_s,

      packet_i => output_paced_s.m,
      packet_o => output_paced_s.s,

      stats_o => stats_bus.m,
      stats_i => stats_bus.s
      );

    stats_bus.s <= accept(config_c(i), true);

    dropped_pkt_proc : process(in_clock_s)
      variable wait_end_sim_v : integer := 20000;
    begin 
      if rising_edge(in_clock_s) then
        if is_valid(config_c(i), input_s.m) and is_last(config_c(i), input_s.m) and is_ready(config_c(i), input_s.s) then
          if overrun_s = '1' then
            nbr_dropped_pkts_v <= nbr_dropped_pkts_v + 1;
          end if;
          nbr_pkts_played_v <= nbr_pkts_played_v + 1;
          if nbr_pkts_played_v > 0 then
            drop_pkt_proportion <= (real(nbr_dropped_pkts_v) / real(nbr_pkts_played_v)) * 100.0;
          end if;
          if (nbr_pkts_played_v mod 100 = 0) then
            log_info("==== DYNAMIC STATS SCENARIO " & to_string(i) & " ====");
            log_info("INFO: Number packets played " & to_string(nbr_pkts_played_v));
            log_info("INFO: Number packets dropped " & to_string(nbr_dropped_pkts_v));
            log_info("INFO: Number packets out " & to_string(nbr_pkt_out_v));
            log_info("INFO: Number sequm error detected " & to_string(nbr_header_seqnum_error_detected_v));
            log_info("INFO: Max dropped packets in a row " & to_string(max_drop_pkt_row_v));
            log_info("INFO: Pourcentage of dropped packets " & to_string(drop_pkt_proportion) & " %");
            log_info(" ");
          end if;
        end if;
        if pkt_to_play_c <= nbr_pkts_played_v then
          if wait_end_sim_v = 0 then
            log_info("==== **  FINAL STATS " & to_string(i) & " ** ====");
            log_info("INFO: Number packets played " & to_string(nbr_pkts_played_v));
            log_info("INFO: Number packets dropped " & to_string(nbr_dropped_pkts_v));
            log_info("INFO: Number packets out " & to_string(nbr_pkt_out_v));
            log_info("INFO: Number sequm error detected " & to_string(nbr_header_seqnum_error_detected_v));
            log_info("INFO: Max dropped packets in a row " & to_string(max_drop_pkt_row_v));
            log_info("INFO: Pourcentage of dropped packets " & to_string(drop_pkt_proportion) & " %");
            if nbr_pkts_played_v /= (nbr_dropped_pkts_v + nbr_pkt_out_v) then
              assert false
              report "ERROR: Packets where lost."
              severity failure;
            end if;
            done_s(i) <= '1';
          else
            wait_end_sim_v := wait_end_sim_v - 1;
          end if;
        end if;
      end if;
    end process;

    check_proc : process(out_clock_s)
      variable stats_v : stats_t;
      variable nbr_drop_pkt_row_v : integer := 0;
    begin 

      stats_v := stats_unpack(bytes(stats_config_default_c, stats_bus.m));

      if rising_edge(out_clock_s) then
        if is_valid(config_c(i), output_s.m) and 
            is_ready(config_c(i), output_s.s) and 
            is_last(config_c(i), output_s.m) then
          nbr_pkt_out_v <= nbr_pkt_out_v + 1;
        end if;

        if is_valid(stats_config_default_c, stats_bus.m) and 
           is_ready(stats_config_default_c, stats_bus.s) and 
           is_last(stats_config_default_c, stats_bus.m) then
          if not stats_v.header_valid then
            nbr_drop_pkt_row_v := nbr_drop_pkt_row_v + 1;
            nbr_header_seqnum_error_detected_v <= nbr_header_seqnum_error_detected_v + 1;
          elsif not stats_v.payload_valid then
            assert false
            report "ERROR: invalid payload."
            severity failure;
          else
            nbr_drop_pkt_row_v := 0;
          end if;
          if nbr_drop_pkt_row_v > max_drop_pkt_row_v then
            max_drop_pkt_row_v <= nbr_drop_pkt_row_v + 1;
          end if;
          if nbr_drop_pkt_row_v = max_error_in_a_row_c then
            log_info("INFO: number packets player " & to_string(nbr_pkts_played_v));
            log_info("INFO: number packets dropped " & to_string(nbr_dropped_pkts_v));
            assert false
            report "ERROR: Too much drop in a row (" & to_string(nbr_drop_pkt_row_v) & " drop)."
            severity failure;
          end if;
        end if;
      end if;
    end process;

  -- dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
  --   generic map(
  --     config_c => config_c(i),
  --     prefix_c => "IN SCENARIO " & to_string(i)
  --     )
  --   port map(
  --     clock_i => in_clock_s,
  --     reset_n_i => in_reset_n_s,

  --     bus_i => input_s
  --     );

  -- dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
  --   generic map(
  --     config_c => config_c(i),
  --     prefix_c => "OUT SCENARIO " & to_string(i)
  --     )
  --   port map(
  --     clock_i => out_clock_s,
  --     reset_n_i => out_reset_n_s,

  --     bus_i => output_s
  --     );

  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 2,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 5 ns,
      clock_period(1) => 6 ns,
      reset_duration => (others => 100 ns),
      clock_o(0) => in_clock_s,
      clock_o(1) => out_clock_s,
      reset_n_o(0) => in_reset_n_s,
      reset_n_o(1) => out_reset_n_s,
      done_i => done_s
      );
end;
