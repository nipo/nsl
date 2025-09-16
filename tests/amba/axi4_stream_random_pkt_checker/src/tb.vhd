library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.random_pkt_checker.all;

entity tb is
  generic(
    insert_error_c : boolean := false;
    scenario_c : natural := 0
  );
end tb;

architecture arch of tb is

  type stream_cfg_array_t is array (natural range <>) of config_t;
  type error_feedback_array_t is array (natural range <>) of error_feedback_t;

  constant nbr_scenario : integer := 2;

  constant stats_printer_bus : config_t := 
    (config(8, keep => true, last => true));

  constant tx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(1, keep => true, last => true),
     1 => config(4, keep => true, last => true),
     2 => config(4, keep => true, last => true));

  constant rx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(4, keep => true, last => true),
     1 => config(1, keep => true, last => true),
     2 => config(4, keep => true, last => true));

  constant header_crc_params : crc_params_t := crc_params(
    init             => "",
    poly             => x"18005",
    complement_input => false,
    complement_state => false,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );

  constant mtu_c : integer := 1500;
  constant NBR_PKT_TO_TEST : integer := 10000;
  constant probability_denom_l2_c : integer range 1 to 31 := 31;
  constant probability_c : real := 0.01;
  constant mode_c : string(1 to 6) := "RANDOM";
  constant max_errors_per_scenario_c : natural := 250;

  function to_string(stats : stats_t) return string is
    constant line_sep : string := "+----------------------------+";
    variable header_valid_str  : string(1 to 5);
    variable payload_valid_str : string(1 to 5);
  begin
    -- Convert booleans to string
    if stats.stats_header_valid then
      header_valid_str := "TRUE ";
    else
      header_valid_str := "FALSE";
    end if;
  
    if stats.stats_payload_valid then
      payload_valid_str := "TRUE ";
    else
      payload_valid_str := "FALSE";
    end if;
  
    return LF &
            "+----------------------------+" & LF &
            "|        STATS REPORT        |" & LF &
            line_sep & LF &
            "| Seq Num       : " & integer'image(to_integer(stats.stats_seqnum)) & LF &
            "| Packet Size   : " & integer'image(to_integer(stats.stats_pkt_size)) & LF &
            "| Header Valid  : " & header_valid_str & LF &
            "| Payload Valid : " & payload_valid_str & LF &
            "| Index Data KO : " & integer'image(to_integer(stats.stats_index_data_ko)) & LF &
            "+----------------------------+";
  end function;

  signal clock_i_s : std_ulogic;
  signal reset_n_i_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  
  signal feed_back_s : error_feedback_t;
  signal insert_error_s : boolean := false;
  signal byte_index_s : integer range 0 to rx_stream_cfg_array(scenario_c).data_width := 0;

  signal cmd_bus, tx_bus,rx_bus,stats_bus,asserter_bus, adapter_bus, err_inserter_bus, stats_adpater_bus, asserter_back_pressure_bus, pkt_validator_rand_back_pressure_bus  : bus_t;

begin
  
  cmd_gen : nsl_amba.random_pkt_checker.random_cmd_generator
    generic map (
      mtu_c => mtu_c,
      config_c => tx_stream_cfg_array(scenario_c)
      )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
      --
      enable_i => '1',
      --
      out_o => cmd_bus.m,
      out_i => cmd_bus.s
      );

  pkt_gen : nsl_amba.random_pkt_checker.random_pkt_generator
    generic map (
      mtu_c => mtu_c,
      config_c => tx_stream_cfg_array(scenario_c),
      data_prbs_init => x"deadbee"&"111",
      data_prbs_poly => prbs31,
      header_crc_params_c => header_crc_params
      )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
      --
      in_i => cmd_bus.m,
      in_o => cmd_bus.s,
      --
      out_o => tx_bus.m,
      out_i => tx_bus.s
      );

  axi4_stream_medium_width_adapter : nsl_amba.axi4_stream.axi4_stream_width_adapter
    generic map (
      in_config_c => tx_stream_cfg_array(scenario_c),
      out_config_c => rx_stream_cfg_array(scenario_c)
    )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,

      in_i => tx_bus.m,
      in_o => tx_bus.s,

      out_o => adapter_bus.m,
      out_i => adapter_bus.s
    );

  error_inserter : nsl_amba.axi4_stream.axi4_stream_error_inserter
    generic map (
      config_c => rx_stream_cfg_array(scenario_c),
      probability_denom_l2_c => probability_denom_l2_c,
      probability_c => probability_c,
      mode_c => mode_c,
      mtu_c => mtu_c
      )
    port map(
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,

      insert_error_i => insert_error_s,
      byte_index_i => byte_index_s,

      in_i => adapter_bus.m,
      in_o => adapter_bus.s,

      out_o => err_inserter_bus.m,
      out_i => err_inserter_bus.s,

      feed_back_o => feed_back_s
      );


  pkt_checker : nsl_amba.random_pkt_checker.random_pkt_validator
    generic map (
      mtu_c => mtu_c,
      config_c => rx_stream_cfg_array(scenario_c),
      data_prbs_poly => prbs31,
      header_crc_params_c => header_crc_params
      )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
      --
      in_i => err_inserter_bus.m,
      in_o => err_inserter_bus.s,
      --
      out_o => stats_bus.m,
      out_i => stats_bus.s
      );

  pkt_validator_rand_back_pressure: nsl_amba.axi4_stream.axi4_stream_pacer
    generic map(
      config_c => rx_stream_cfg_array(scenario_c),
      probability_c => 0.55
      )
    port map(
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
  
      in_i => stats_bus.m,
      in_o => stats_bus.s,
  
      out_o => pkt_validator_rand_back_pressure_bus.m,
      out_i => pkt_validator_rand_back_pressure_bus.s
      );

  axi4_stream_stats_width_adapter : nsl_amba.axi4_stream.axi4_stream_width_adapter
    generic map (
      in_config_c => rx_stream_cfg_array(scenario_c),
      out_config_c => stats_printer_bus
    )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,

      in_i => pkt_validator_rand_back_pressure_bus.m,
      in_o => pkt_validator_rand_back_pressure_bus.s,

      out_o => stats_adpater_bus.m,
      out_i => stats_adpater_bus.s
    );

  stats_asserter : nsl_amba.random_pkt_checker.random_stats_asserter
    generic map (
      mtu_c => mtu_c,
      config_c => stats_printer_bus
      )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
      --
      in_i => stats_adpater_bus.m,
      in_o => stats_adpater_bus.s,
      --
      out_o => asserter_bus.m,
      out_i => asserter_bus.s
      );

  assert_rand_back_pressure: nsl_amba.axi4_stream.axi4_stream_pacer
    generic map(
      config_c => stats_printer_bus,
      probability_c => 0.2
      )
    port map(
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
  
      in_i => asserter_bus.m,
      in_o => asserter_bus.s,
  
      out_o => asserter_back_pressure_bus.m,
      out_i => asserter_back_pressure_bus.s
      );

  asserter_back_pressure_bus.s <= (accept(stats_printer_bus, true));

  stats_proc : process(clock_i_s)
    variable tested_pkts : integer := 0;
    variable stats_v : stats_t;
    variable feedback_v : error_feedback_array_t(0 to max_errors_per_scenario_c-1);
    variable read_ptr, err_cnt_v : integer := 0;
    variable rx_bytes_v : integer range 0 to mtu_c := 0;
    variable header_prev_error_v : boolean := false;
  begin 
    if reset_n_i_s = '0' then
      null;
    elsif rising_edge(clock_i_s) then
      if is_valid(rx_stream_cfg_array(scenario_c), err_inserter_bus.m) and is_ready(rx_stream_cfg_array(scenario_c), err_inserter_bus.s) then
        rx_bytes_v := rx_bytes_v + rx_stream_cfg_array(scenario_c).data_width;
        if feed_back_s.error = '1' then
          -- We check the HEADER as a chunk so if two 
          -- errors are inserted in the header, only the first 
          -- one will be detected and will generate a stats feedback
          if rx_bytes_v <= HEADER_SIZE then
            if not header_prev_error_v then
              feedback_v(err_cnt_v) := feed_back_s;
              err_cnt_v := (err_cnt_v + 1) mod feedback_v'length;
              header_prev_error_v := true;
            end if;
          else
            feedback_v(err_cnt_v) := feed_back_s;
            err_cnt_v := (err_cnt_v + 1) mod feedback_v'length;
          end if;
        end if;
      end if;
      --
      if is_valid(rx_stream_cfg_array(scenario_c), err_inserter_bus.m) and is_ready(rx_stream_cfg_array(scenario_c), err_inserter_bus.s) then
        if is_last(rx_stream_cfg_array(scenario_c), err_inserter_bus.m) then
          tested_pkts := tested_pkts + 1;
          header_prev_error_v := false;
          rx_bytes_v := 0;
        end if;
      end if;
      -- Stats Check
      if is_ready(stats_printer_bus, stats_adpater_bus.s) and is_valid(stats_printer_bus, stats_adpater_bus.m) then
        stats_v := stats_unpack(bytes(stats_printer_bus, stats_adpater_bus.m));
        --
        if not stats_v.stats_payload_valid or not stats_v.stats_header_valid then
          -- This distinction is necessary in the case of an inserted error in the 
          -- packet size. Since we use the received packet size field to generate 
          -- a reference header, an error inserted in this field will be detected 
          -- in the random data and not directly in the size field.
          if feedback_v(read_ptr).pkt_index_ko = 2 or 
             feedback_v(read_ptr).pkt_index_ko = 3 then
            log_info("DUMPED KO STATS" & " - " & to_string(stats_v));
            log_info("DEBUG: read_ptr=" & to_string(read_ptr) &
                    ", err_cnt_v=" & to_string(err_cnt_v) &
                    ", feedback(pkt_index_ko)=" & to_string(feedback_v(read_ptr).pkt_index_ko));
            assert (stats_v.stats_index_data_ko = 4 or 
                  stats_v.stats_index_data_ko = 5)
            report "ERROR: Stats error should be in rand data."
            severity failure;
          else
            log_info("DUMPED KO STATS" & " - " & to_string(stats_v));
            log_info("DEBUG: read_ptr=" & to_string(read_ptr) &
                    ", err_cnt_v=" & to_string(err_cnt_v) &
                    ", feedback(pkt_index_ko)=" & to_string(feedback_v(read_ptr).pkt_index_ko));

            assert stats_v.stats_index_data_ko = feedback_v(read_ptr).pkt_index_ko
            report "ERROR: pkt index ko does not match."
            severity failure;
          end if;
          read_ptr := (read_ptr + 1) mod feedback_v'length;
        end if;
        --
        if (tested_pkts mod 1000 = 0 ) then
          log_info("PERIODIC STATS DUMP : " & " - " & to_string(stats_v));
        end if;
        --
        if to_integer(stats_v.stats_pkt_size) > mtu_c then
          log_info("INFO: Pkt Size = " & to_string(stats_v.stats_pkt_size));
          assert false report " ERROR: ERROR: Size cannot be supp to mtu" severity failure;
        end if;
        -- 
        if tested_pkts = NBR_PKT_TO_TEST then
          if err_cnt_v /= read_ptr then
            if err_cnt_v > read_ptr then
              log_info("ERROR: err_cnt_v " & to_string(err_cnt_v) & " > read_ptr " & to_string(read_ptr));
              assert false severity failure;
            else 
              log_info("ERROR: err_cnt_v " & to_string(err_cnt_v) & " < read_ptr " & to_string(read_ptr));
              assert false severity failure;
            end if;
          end if;
          done_s <= (others => '1');
        end if;
      end if;
    end if;
  end process;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_i_s,
      reset_n_o(0) => reset_n_i_s,
      done_i => done_s
      );
  
end;
