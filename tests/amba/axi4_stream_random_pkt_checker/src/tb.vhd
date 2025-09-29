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
end tb;

architecture arch of tb is
  constant max_errors_per_scenario_c : natural := 250;
  constant mtu_c : integer := 500;
  constant nbr_pkt_to_test : integer := 10000;
  constant probability_denom_l2_c : integer range 1 to 31 := 31;
  constant probability_c : real := 0.01;
  constant mode_c : string(1 to 6) := "RANDOM";
  constant nbr_scenario : integer := 3;
  constant inter_pkt_gap_size : integer := 10;
  constant pkt_disappearance_rate : integer := 20;

  type stream_cfg_array_t is array (natural range <>) of config_t;
  type error_feedback_array_array_t is array (natural range <>) of error_feedback_array_t(0 to max_errors_per_scenario_c - 1);
  type integer_vector is array (natural range <>) of integer;
  type stats_array_t is array (natural range <> ) of stats_t;
  subtype int_0_to_2_t is integer range 0 to mtu_c;
  type integer_vector_0_to_mtu_t is array (natural range <>) of int_0_to_2_t;
  type boolean_vector is array (natural range <> ) of boolean;
  --
  type size_distribution_t is array (0 to nbr_scenario - 1) of integer_vector(0 to mtu_c);
  type index_ko_t is array (0 to nbr_scenario - 1) of integer_vector(0 to mtu_c);
  constant seqnum_err_because_of_pkt_drop : error_feedback_t := (error => '1',
                                                 pkt_index_ko => to_unsigned(0, 16));
  constant pkt_size_error : error_feedback_t := (error => '1',
                                                 pkt_index_ko => to_unsigned(15, 16));
  constant feedback_default : error_feedback_t := (error => '0',
                                                   pkt_index_ko => to_unsigned(0, 16));
  
  type state_t is (
    ST_IDLE,
    ST_CNT,
    ST_PKT_DROP
    );

  type state_vector_t is array (natural range <> ) of state_t;
                                                
  constant stats_printer_bus : config_t := 
    (config(8, keep => true, last => true));

  constant tx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(4, keep => true, last => true), -- 4
     1 => config(2, keep => true, last => true), -- 2
     2 => config(2, keep => true, last => true));-- 2

  constant rx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(2, keep => true, last => true), -- 2
     1 => config(4, keep => true, last => true), -- 4
     2 => config(2, keep => true, last => true));-- 2

  constant header_crc_params : crc_params_t := crc_params(
    init             => "",
    poly             => x"18005",
    complement_input => false,
    complement_state => false,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );

  function to_string(
    stats      : stats_t; 
    scenario   : integer; 
    tx_stream  : config_t; 
    rx_stream  : config_t
  ) return string is
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
  
    -- Build report string
    return LF &
            "+----------------------------+" & LF &
            "|        SCENARIO REPORT     |" & LF &
            line_sep & LF &
            "| Scenario      : " & to_string(scenario) & LF &
            "| TX Config     : width=" & to_string(tx_stream.data_width) &
                              ", has_keep=" & boolean'image(tx_stream.has_keep) &
                              ", has_last=" & boolean'image(tx_stream.has_last) & LF &
            "| RX Config     : width=" & to_string(rx_stream.data_width) &
                              ", has_keep=" & boolean'image(rx_stream.has_keep) &
                              ", has_last=" & boolean'image(rx_stream.has_last) & LF &
            line_sep & LF &
            "|        STATS REPORT        |" & LF &
            line_sep & LF &
            "| Seq Num       : " & to_string(to_integer(stats.stats_seqnum)) & LF &
            "| Packet Size   : " & to_string(to_integer(stats.stats_pkt_size)) & LF &
            "| Header Valid  : " & header_valid_str & LF &
            "| Payload Valid : " & payload_valid_str & LF &
            "| Index Data KO : " & to_string(to_integer(stats.stats_index_data_ko)) & LF &
            "+----------------------------+";
  end function;
  
  signal clock_i_s : std_ulogic;
  signal reset_n_i_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario - 1);
  
  signal feed_back_s, feed_back_ipg_s : error_feedback_array_t(0 to nbr_scenario - 1);
  signal assert_error_s : std_ulogic_vector( 0 to nbr_scenario - 1);
  signal insert_error_s : boolean_vector(0 to nbr_scenario - 1) := (others => false);
  signal toggle_s, toggle_adapt_s  : std_ulogic_vector(0 to nbr_scenario - 1);
  -- STATISTICS
  signal pkt_size_distribution_s : size_distribution_t := (others => (others => 0));
  signal index_data_ko_distribution_s : index_ko_t := (others => (others => 0));
  signal pkt_dumped_cnt_s : integer_vector(0 to nbr_scenario - 1) := (others => 0);
  shared variable dump_pkt_trigger_sh_v, ignore_pkt_sh_v : boolean_vector(0 to nbr_scenario - 1) := (others => false);

  signal state_s : state_vector_t(0 to nbr_scenario - 1);

  shared variable done_s_tmp : std_ulogic_vector(0 to nbr_scenario - 1);
  shared variable pkt_gen_size_array_v : integer_vector (0 to max_errors_per_scenario_c - 1) := (others => 0);


  signal cmd_bus, tx_bus ,stats_bus ,adapter_bus, adapter_ipg_bus, err_inserter_bus : bus_vector(0 to nbr_scenario - 1);

begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate
    constant cmd_buf_config_c : buffer_config_t := buffer_config(tx_stream_cfg_array(i), CMD_SIZE);
    constant stats_buf_config_c : buffer_config_t := buffer_config(rx_stream_cfg_array(i), STATS_SIZE+1);
    signal byte_index_s : integer range 0 to rx_stream_cfg_array(i).data_width;
  begin
    cmd_gen : nsl_amba.random_pkt_checker.random_cmd_generator
      generic map (
        mtu_c => mtu_c,
        config_c => tx_stream_cfg_array(i)
        )
      port map (
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,
        --
        enable_i => '1',
        --
        out_o => cmd_bus(i).m,
        out_i => cmd_bus(i).s
        );

    pkt_gen : nsl_amba.random_pkt_checker.random_pkt_generator
      generic map (
        mtu_c => mtu_c,
        config_c => tx_stream_cfg_array(i),
        data_prbs_init => x"deadbee"&"111",
        data_prbs_poly => prbs31,
        header_crc_params_c => header_crc_params
        )
      port map (
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,
        --
        in_i => cmd_bus(i).m,
        in_o => cmd_bus(i).s,
        --
        out_o => tx_bus(i).m,
        out_i => tx_bus(i).s
        );

    axi4_stream_medium_width_adapter : nsl_amba.axi4_stream.axi4_stream_width_adapter
      generic map (
        in_config_c => tx_stream_cfg_array(i),
        out_config_c => rx_stream_cfg_array(i)
      )
      port map (
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,

        in_i => tx_bus(i).m,
        in_o => tx_bus(i).s,

        out_o => adapter_bus(i).m,
        out_i => adapter_bus(i).s
      );

    error_inserter : nsl_amba.axi4_stream.axi4_stream_error_inserter
      generic map (
        config_c => rx_stream_cfg_array(i),
        probability_denom_l2_c => probability_denom_l2_c,
        probability_c => probability_c,
        mode_c => mode_c,
        mtu_c => mtu_c
        )
      port map(
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,

        insert_error_i => insert_error_s(i),
        byte_index_i => byte_index_s,

        in_i => adapter_bus(i).m,
        in_o => adapter_bus(i).s,

        out_o => err_inserter_bus(i).m,
        out_i => err_inserter_bus(i).s,

        feed_back_o => feed_back_s(i)
        );

    inter_pkt_gap_proc : process(clock_i_s)
      variable ipg_cnt_v, pkt_cnt_v : integer_vector(0 to nbr_scenario - 1) := (others => 0);
    begin
      if reset_n_i_s = '0' then
        state_s(i) <= ST_IDLE;
      elsif rising_edge(clock_i_s) then
        case state_s(i) is
          when ST_IDLE => 
            dump_pkt_trigger_sh_v(i) := false;
            if is_valid(rx_stream_cfg_array(i), err_inserter_bus(i).m) and is_ready(rx_stream_cfg_array(i), err_inserter_bus(i).s) then
              if is_last(rx_stream_cfg_array(i), err_inserter_bus(i).m) then
                pkt_cnt_v(i) := pkt_cnt_v(i) + 1;
                ignore_pkt_sh_v(i) := false;
                state_s(i) <= ST_CNT;
              end if;
            end if;

          when ST_CNT =>
            ipg_cnt_v(i) := ipg_cnt_v(i) + 1;
            dump_pkt_trigger_sh_v(i) := false;
            ignore_pkt_sh_v(i) := false;
            if ipg_cnt_v(i) = inter_pkt_gap_size then
              ipg_cnt_v(i) := 0;
              if (pkt_cnt_v(i) mod pkt_disappearance_rate) = 0 then
                state_s(i) <= ST_PKT_DROP;
              else
                state_s(i) <= ST_IDLE;
              end if;
            end if;

            when ST_PKT_DROP => 
              ignore_pkt_sh_v(i) := true;
              if is_valid(rx_stream_cfg_array(i), err_inserter_bus(i).m) and is_ready(rx_stream_cfg_array(i), err_inserter_bus(i).s) then
                if is_last(rx_stream_cfg_array(i), err_inserter_bus(i).m) then
                  pkt_dumped_cnt_s(i) <= pkt_dumped_cnt_s(i) + 1;
                  dump_pkt_trigger_sh_v(i) := true;
                  state_s(i) <= ST_IDLE;
                end if;
              end if;
        end case;
      end if;
    end process;

    err_inserter_bus(i).s <= accept(rx_stream_cfg_array(i), false) when state_s(i) = ST_CNT else adapter_ipg_bus(i).s;
    adapter_ipg_bus(i).m <= err_inserter_bus(i).m when state_s(i) = ST_IDLE else transfer_defaults(rx_stream_cfg_array(i));
    feed_back_ipg_s(i) <= feedback_default when ignore_pkt_sh_v(i) else feed_back_s(i);

    pkt_checker : nsl_amba.random_pkt_checker.random_pkt_validator
      generic map (
        mtu_c => mtu_c,
        config_c => rx_stream_cfg_array(i),
        data_prbs_poly => prbs31,
        header_crc_params_c => header_crc_params
        )
      port map (
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,
        --
        in_i => adapter_ipg_bus(i).m,
        in_o => adapter_ipg_bus(i).s,
        --
        out_o => stats_bus(i).m,
        out_i => stats_bus(i).s,
        toggle_o => toggle_s(i)
        );

    stats_asserter : nsl_amba.random_pkt_checker.random_stats_asserter
      generic map (
        config_c => rx_stream_cfg_array(i)
        )
      port map (
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,
        --
        in_i => stats_bus(i).m,
        in_o => stats_bus(i).s,
        --
        toggle_i => toggle_s(i),
        --
        feedback_i => feed_back_ipg_s(i),
        assert_error_o => assert_error_s(i)
        );

    stats_proc : process(clock_i_s)
      variable tested_pkts_v : integer := 0;
      variable stats_v : stats_t;
      variable read_ptr_v, write_pkt_size_ptr,  write_ptr_v, read_pkt_size_ptr: integer := 0;
      variable rx_bytes_v : integer range 0 to mtu_c;
      variable stats_buf : buffer_t := reset(stats_buf_config_c);
      variable cmd_buf_v : buffer_t := reset(cmd_buf_config_c);
      variable wrong_pkt_size_v, wrong_pkt_seqnum_v, wrong_pkt_rand_data_v, ignore_err_v, size_error_last_stats_report_v, pkt_has_data_v, pkt_last_v, one_stats_report_remaining_v, reset_all_var_v, header_prev_error_v : boolean := false;
      variable pkt_gen_size_array_v : integer_vector (0 to max_errors_per_scenario_c - 1) := (others => 0);
      -- Statistics collection
      variable pkt_size_distribution_v :integer_vector(0 to mtu_c) := (others => 0);
      variable index_data_ko_distribution_v : integer_vector(0 to mtu_c) := (others => 0);
      variable feedback_array_v : error_feedback_array_t(0 to max_errors_per_scenario_c - 1);
    begin 
      if reset_n_i_s = '0' then
        null;
      elsif rising_edge(clock_i_s) then

        assert assert_error_s(i) = '0' 
        report "ERROR: stats asserter of scenario : " & to_string(i) &" must not trigger."
        severity failure;

        if done_s_tmp(i) /= '1' then
          --
          if is_valid(tx_stream_cfg_array(i), cmd_bus(i).m) and is_ready(tx_stream_cfg_array(i), cmd_bus(i).s) then
            cmd_buf_v := shift(cmd_buf_config_c, cmd_buf_v, cmd_bus(i).m);
            if is_last(tx_stream_cfg_array(i), cmd_bus(i).m) then
              pkt_gen_size_array_v(write_pkt_size_ptr) := to_integer(cmd_unpack(bytes(cmd_buf_config_c, cmd_buf_v)).cmd_pkt_size);
              write_pkt_size_ptr := (write_pkt_size_ptr + 1) mod pkt_gen_size_array_v'length;
            end if;
          end if;
          --
          if feed_back_s(i).error = '1' then
            if is_seqnum_corrupted(feed_back_s(i).pkt_index_ko) then
              wrong_pkt_seqnum_v := true;
            end if;
            -- 
            if is_size_corrupted(feed_back_s(i).pkt_index_ko) then
              wrong_pkt_size_v := true;
            end if;
            -- 
            if is_rand_data_corrupted(feed_back_s(i).pkt_index_ko) then
              wrong_pkt_rand_data_v := true;
            end if;
          end if;
          --
          if dump_pkt_trigger_sh_v(i) then
            feedback_array_v(write_ptr_v) := seqnum_err_because_of_pkt_drop;
            write_ptr_v := (write_ptr_v + 1) mod feedback_array_v'length;
            read_pkt_size_ptr := (read_pkt_size_ptr + 1) mod pkt_gen_size_array_v'length;
            feedback_array_v(write_ptr_v).error := '0';
          end if;
          --
          pkt_has_data_v := pkt_gen_size_array_v(read_pkt_size_ptr) > HEADER_SIZE;
          size_error_last_stats_report_v := pkt_has_data_v and wrong_pkt_size_v;
          --
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) then
            rx_bytes_v := rx_bytes_v + count_valid_bytes(keep(rx_stream_cfg_array(i), adapter_ipg_bus(i).m));
          end if;
          --
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) then
            if ((rx_bytes_v > HEADER_SIZE) and (wrong_pkt_size_v or wrong_pkt_seqnum_v or wrong_pkt_rand_data_v)) or ignore_pkt_sh_v(i) then
              ignore_err_v := true;
            end if;
          end if;
          --
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) then
            if not ignore_err_v then
              if is_last(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) then
                if size_error_last_stats_report_v then
                  feedback_array_v(write_ptr_v) := pkt_size_error;
                  write_ptr_v := (write_ptr_v + 1) mod feedback_array_v'length;
                else
                  if feed_back_s(i).error = '1' then
                    if rx_bytes_v <= HEADER_SIZE then
                      if not header_prev_error_v then -- take into account only one error in the header
                        feedback_array_v(write_ptr_v) := feed_back_s(i);
                        header_prev_error_v := true;
                        write_ptr_v := (write_ptr_v + 1) mod feedback_array_v'length;
                      end if;
                    else
                      feedback_array_v(write_ptr_v) := feed_back_s(i);
                      write_ptr_v := (write_ptr_v + 1) mod feedback_array_v'length;
                    end if;
                  end if;
                end if;
              else
                if feed_back_s(i).error = '1' then
                  if rx_bytes_v <= HEADER_SIZE then
                    if not header_prev_error_v then -- take into account only one error in the header
                      feedback_array_v(write_ptr_v) := feed_back_s(i);
                      header_prev_error_v := true;
                      write_ptr_v := (write_ptr_v + 1) mod feedback_array_v'length;
                    end if;
                  else
                    feedback_array_v(write_ptr_v) := feed_back_s(i);
                    write_ptr_v := (write_ptr_v + 1) mod feedback_array_v'length;
                  end if;
                end if;
              end if;
              feedback_array_v(write_ptr_v).error := '0';
            end if;
          end if;
          --
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) then
            if is_last(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) then
              wrong_pkt_size_v := false;
              wrong_pkt_seqnum_v := false;
              wrong_pkt_rand_data_v := false;
              ignore_err_v := false;
              size_error_last_stats_report_v := false;
              header_prev_error_v := false;
            end if;
          end if;
          -- Stats check and processing
          if is_ready(stats_printer_bus, stats_bus(i).s) and is_valid(stats_printer_bus, stats_bus(i).m) then
            stats_buf := shift(stats_buf_config_c, stats_buf, stats_bus(i).m);
            if is_last(stats_buf_config_c, stats_buf) then
              stats_buf := shift(stats_buf_config_c, stats_buf, stats_bus(i).m);
              stats_v := stats_unpack(bytes(stats_buf_config_c, stats_buf));
  
              if not stats_v.stats_payload_valid or not stats_v.stats_header_valid then
                index_data_ko_distribution_v(to_integer(stats_v.stats_index_data_ko)) := 
                  index_data_ko_distribution_v(to_integer(stats_v.stats_index_data_ko)) + 1;
                if (feedback_array_v(read_ptr_v).pkt_index_ko = 2 or 
                    feedback_array_v(read_ptr_v).pkt_index_ko = 3) and (pkt_has_data_v) then
                      log_info("DUMPED KO HEADER STATS" & " - " & to_string(stats_v, i, tx_stream_cfg_array(i), rx_stream_cfg_array(i)));
                      log_info("DEBUG: read_ptr_v=" & to_string(read_ptr_v) &
                              ", write_ptr_v=" & to_string(write_ptr_v) &
                              ", read_pkt_size_ptr=" & to_string(read_pkt_size_ptr) &
                              ", write_pkt_size_ptr=" & to_string(write_pkt_size_ptr) &
                              ", gen_size_array= " & to_string(pkt_gen_size_array_v(read_pkt_size_ptr)) &
                              ", feedback(2)=" & to_string(feedback_array_v(2).pkt_index_ko) & 
                              ", feedback(read_ptr_v)=" & to_string(feedback_array_v(read_ptr_v).pkt_index_ko));
                        assert (stats_v.stats_index_data_ko = 4 or 
                                stats_v.stats_index_data_ko = 5)
                          report "ERROR: Stats error should be in rand data."
                          severity failure;     
                else
                  log_info("DUMPED KO STATS" & " - " & to_string(stats_v, i, tx_stream_cfg_array(i), rx_stream_cfg_array(i)));
                  log_info("DEBUG: read_ptr_v=" & to_string(read_ptr_v) &
                          ", write_ptr_v=" & to_string(write_ptr_v) &
                          ", read_pkt_size_ptr=" & to_string(read_pkt_size_ptr) &
                          ", write_pkt_size_ptr=" & to_string(write_pkt_size_ptr) &
                          ", gen_size_array= " & to_string(pkt_gen_size_array_v(read_pkt_size_ptr)) &
                          ", feedback(read_ptr_v)=" & to_string(feedback_array_v(read_ptr_v).pkt_index_ko) &
                          ", feedback(read_ptr_v + 1)=" & to_string(feedback_array_v((read_ptr_v + 1) mod feedback_array_v'length).pkt_index_ko) &
                          ", feedback(read_ptr_v - 1)=" & to_string(feedback_array_v((read_ptr_v - 1) mod feedback_array_v'length).pkt_index_ko));
                    assert stats_v.stats_index_data_ko = feedback_array_v(read_ptr_v).pkt_index_ko
                    report "ERROR: pkt index ko does not match."
                    severity failure;
                end if;
                read_ptr_v := (read_ptr_v + 1) mod feedback_array_v'length;
              end if;
            end if;
          end if;
          -- Reset variables
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) then
            if is_last(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) then
              pkt_size_distribution_v(rx_bytes_v) := 
                pkt_size_distribution_v(rx_bytes_v) + 1;
              one_stats_report_remaining_v := false;
              rx_bytes_v := 0;
              tested_pkts_v := tested_pkts_v + 1;
              if feedback_array_v(read_ptr_v).error = '1' then
                one_stats_report_remaining_v := true;
              else
                reset_all_var_v := true;
              end if;
            end if;
          end if;
          --
          if one_stats_report_remaining_v then
            -- log_info("IN ONE STATS REPORT REMAINING");
            if is_ready(stats_printer_bus, stats_bus(i).s) and is_valid(stats_printer_bus, stats_bus(i).m) then
              if is_last(stats_printer_bus, stats_bus(i).m) then
                  reset_all_var_v := true;
              end if;
            end if;
          end if;
          --
          if reset_all_var_v then
            read_pkt_size_ptr := (read_pkt_size_ptr + 1) mod pkt_gen_size_array_v'length;
            reset_all_var_v := false;
            one_stats_report_remaining_v := false;
          end if;
          --
          if tested_pkts_v > nbr_pkt_to_test then
            pkt_size_distribution_s(i) <= pkt_size_distribution_v;
            index_data_ko_distribution_s(i) <= index_data_ko_distribution_v;
            done_s_tmp(i) := '1';
          end if;  
        end if;
      end if;
    end process;  
  end generate;

  -- STATISTICS
  final_stats_proc : process(clock_i_s)
    variable j : integer;
  begin
    if rising_edge(clock_i_s) then
      if done_s_tmp = (done_s_tmp'range => '1') then
        -- Print final statistics for all scenarios
        for s in 0 to nbr_scenario-1 loop
          log_info("SCENARIO " & to_string(s) & " SUMMARY:");
          log_info("Packet size distribution (size:count):");
          for j in 0 to mtu_c loop
            if pkt_size_distribution_s(s)(j) /= 0 then
              log_info("  " & to_string(j) & " : " & to_string(pkt_size_distribution_s(s)(j)));
            end if;
          end loop;
          log_info("Index Data KO distribution (index:count):");
          for j in 0 to mtu_c loop
            if index_data_ko_distribution_s(s)(j) /= 0 then
              log_info("  " & to_string(j) & " : " & to_string(index_data_ko_distribution_s(s)(j)));
            end if;
          end loop;
          log_info("SCENARIO " & to_string(s) & " DUMP PKTS SUMMARY:" & to_string(pkt_dumped_cnt_s(s)));
        end loop;  
        done_s <= done_s_tmp;
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