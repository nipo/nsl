library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;

entity tb is
end tb;

architecture arch of tb is
  constant mtu_c : integer := 50;
  constant nbr_pkt_to_test : integer := 100;
  constant probability_denom_l2_c : integer range 1 to 31 := 31;
  constant probability_c : real := 0.1;
  constant mode_c : error_mode_t := ERROR_MODE_RANDOM;
  constant nbr_scenario : integer := 3;
  constant inter_pkt_gap_size : integer := 100;
  constant pkt_disappearance_rate : integer := 64;
  constant pkt_disappearance_rate_l2 : integer := nsl_math.arith.log2(pkt_disappearance_rate);

  type stream_cfg_array_t is array (natural range <>) of config_t;
  type integer_vector is array (natural range <>) of integer;
  type boolean_vector is array (natural range <> ) of boolean;
  --
  type size_distribution_t is array (0 to nbr_scenario - 1) of integer_vector(0 to mtu_c);
  type index_ko_t is array (0 to nbr_scenario - 1) of integer_vector(0 to mtu_c);
  constant feedback_default : error_feedback_t := (error => '0',
                                                   pkt_index_ko => to_unsigned(0, 16));
  constant header_error : error_feedback_t := (error => '1',
                                               pkt_index_ko => to_unsigned(0, 16));
  
  type state_t is (
    ST_IDLE,
    ST_CNT,
    ST_PKT_DROP
    );

  type incr_state_t is (
    ST_IDLE,
    ST_INCR,
    ST_ASSERT
    );
  
  type state_vector_t is array (natural range <> ) of state_t;
  type incr_state_vector_t is array (natural range <> ) of incr_state_t;
                                                
  constant tx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(2, keep => true, last => true), -- 4
     1 => config(2, keep => true, last => true), -- 2
     2 => config(4, keep => true, last => true), -- 2
     3 => config(8, keep => true, last => true));-- 8
     
  constant rx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(2, keep => true, last => true), -- 2
     1 => config(4, keep => true, last => true), -- 4
     2 => config(4, keep => true, last => true), -- 2
     3 => config(8, keep => true, last => true));-- 8

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
    if stats.header_valid then
      header_valid_str := "TRUE ";
    else
      header_valid_str := "FALSE";
    end if;
  
    if stats.payload_valid then
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
            "| Seq Num       : " & to_string(to_integer(stats.seq_num)) & LF &
            "| Packet Size   : " & to_string(to_integer(stats.pkt_size)) & LF &
            "| Header Valid  : " & header_valid_str & LF &
            "| Payload Valid : " & payload_valid_str & LF &
            "| Index Data KO : " & to_string(to_integer(stats.index_data_ko)) & LF &
            "+----------------------------+";
  end function;

  type buffer_array_t is array (natural range <> ) of buffer_t;
  type regs_t is
    record
      stats_report_cnt : unsigned(5 downto 0);
      injected_error_cnt : unsigned(5 downto 0);
      ipg_cnt : integer range 0 to inter_pkt_gap_size + 1;
      pkt_cnt : unsigned(pkt_disappearance_rate_l2 downto 0);
      state : state_t;
      incr_state : incr_state_t;
      pkt_drop_cnt : integer;
      stats_buf : buffer_t;
    end record;

  signal clock_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario - 1);
  
  signal feed_back_s, feed_back_ipg_s : error_feedback_array_t(0 to nbr_scenario - 1);
  signal insert_error_s : boolean_vector(0 to nbr_scenario - 1) := (others => false);
  -- STATISTICS
  signal pkt_size_distribution_s : size_distribution_t := (others => (others => 0));
  signal index_data_ko_distribution_s : index_ko_t := (others => (others => 0));
  shared variable insert_seq_num_error_sh_v : boolean_vector(0 to nbr_scenario - 1) := (others => false);
  --
  shared variable done_s_tmp : std_ulogic_vector(0 to nbr_scenario - 1);
  signal cmd_bus, tx_bus ,stats_bus, adapter_bus, adapter_ipg_bus, err_inserter_bus : bus_vector(0 to nbr_scenario - 1);

begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate
    signal byte_index_s : integer range 0 to rx_stream_cfg_array(i).data_width;
    constant stats_buf_config_c : buffer_config_t := buffer_config(rx_stream_cfg_array(i), stats_packed_t'length);
    signal r, rin: regs_t;
  begin

    regs: process(clock_s, reset_n_s) is
    begin
      if rising_edge(clock_s) then
        r <= rin;
      end if;
      if reset_n_s = '0' then
        r.stats_report_cnt <= (others => '0');
        r.injected_error_cnt <= (others => '0');
        r.ipg_cnt <= 0;
        r.pkt_cnt <=  (others => '0');
        r.state <=  ST_IDLE;
        r.incr_state <=  ST_IDLE;
        r.pkt_drop_cnt <=  0;
        r.stats_buf <=  reset(stats_buf_config_c);
      end if;
    end process;

    cmd_gen : nsl_amba.stream_traffic.random_cmd_generator
      generic map (
        mtu_c => mtu_c,
        config_c => tx_stream_cfg_array(i),
        min_pkt_size_c => 2
        )
      port map (
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        --
        enable_i => '1',
        --
        cmd_o => cmd_bus(i).m,
        cmd_i => cmd_bus(i).s
        );

    pkt_gen : nsl_amba.stream_traffic.random_pkt_generator
      generic map (
        mtu_c => mtu_c,
        config_c => tx_stream_cfg_array(i)
        )
      port map (
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        --
        cmd_i => cmd_bus(i).m,
        cmd_o => cmd_bus(i).s,
        --
        packet_o => tx_bus(i).m,
        packet_i => tx_bus(i).s
        );

    axi4_stream_medium_width_adapter : nsl_amba.axi4_stream.axi4_stream_width_adapter
      generic map (
        in_config_c => tx_stream_cfg_array(i),
        out_config_c => rx_stream_cfg_array(i)
      )
      port map (
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => tx_bus(i).m,
        in_o => tx_bus(i).s,

        out_o => adapter_bus(i).m,
        out_i => adapter_bus(i).s
      );

    error_inserter : nsl_amba.stream_traffic.stream_error_inserter
      generic map (
        config_c => rx_stream_cfg_array(i),
        probability_denom_l2_c => probability_denom_l2_c,
        probability_c => probability_c,
        mode_c => mode_c,
        mtu_c => mtu_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        insert_error_i => insert_error_s(i),
        byte_index_i => byte_index_s,

        in_i => adapter_bus(i).m,
        in_o => adapter_bus(i).s,

        out_o => err_inserter_bus(i).m,
        out_i => err_inserter_bus(i).s,

        feed_back_o => feed_back_s(i)
        );

    inter_pkt_gap_proc : process(r, err_inserter_bus, stats_bus, feed_back_ipg_s, adapter_ipg_bus)
      variable stats_v : stats_t;
    begin
      rin <= r;

      stats_v := stats_unpack(bytes(stats_buf_config_c, shift(stats_buf_config_c, r.stats_buf, stats_bus(i).m)));

      if is_ready(rx_stream_cfg_array(i), stats_bus(i).s) and is_valid(rx_stream_cfg_array(i), stats_bus(i).m) then
        rin.stats_buf <= shift(stats_buf_config_c, r.stats_buf, stats_bus(i).m);
        if is_last(stats_buf_config_c, r.stats_buf) then
          if not stats_v.payload_valid or not stats_v.header_valid then
            rin.stats_report_cnt <= r.stats_report_cnt + 1;
          end if;
        end if;
      end if;

      case r.incr_state is
        when ST_IDLE =>
          if feed_back_ipg_s(i).error = '1' or r.state = ST_PKT_DROP then
            rin.incr_state <= ST_INCR;
          end if;

        when ST_INCR => 
          if is_ready(rx_stream_cfg_array(i), stats_bus(i).s) and is_valid(rx_stream_cfg_array(i), stats_bus(i).m) then
            if is_last(rx_stream_cfg_array(i), stats_bus(i).m) then
              rin.injected_error_cnt <= r.injected_error_cnt + 1;
              rin.incr_state <= ST_ASSERT;
            end if;
          end if;

        when ST_ASSERT => 
          if r.stats_report_cnt /= r.injected_error_cnt then
            log_info("r.stats_report_cnt = " & to_string(r.stats_report_cnt) & " " & "r.injected_error_cnt= " & to_string(r.injected_error_cnt));
            assert false severity failure;
          end if;
          rin.incr_state <= ST_IDLE;

      end case;

      case r.state is
        when ST_IDLE => 
            if is_valid(rx_stream_cfg_array(i), err_inserter_bus(i).m) and is_ready(rx_stream_cfg_array(i), err_inserter_bus(i).s) then
              insert_seq_num_error_sh_v(i) := false;
              if is_last(rx_stream_cfg_array(i), err_inserter_bus(i).m) then
                rin.pkt_cnt <= r.pkt_cnt + 1;
                rin.state <= ST_CNT;
              end if;
            end if;

          when ST_CNT =>
            rin.ipg_cnt <= r.ipg_cnt + 1;
            if r.ipg_cnt = inter_pkt_gap_size then
              rin.ipg_cnt <= 0;
              if (r.pkt_cnt(pkt_disappearance_rate_l2 -1 downto 0)) = 0 then
                rin.state <= ST_PKT_DROP;
              else
                rin.state <= ST_IDLE;
              end if;
            end if;

          when ST_PKT_DROP => 
            if is_valid(rx_stream_cfg_array(i), err_inserter_bus(i).m) and is_ready(rx_stream_cfg_array(i), err_inserter_bus(i).s) then
              if is_last(rx_stream_cfg_array(i), err_inserter_bus(i).m) then
                rin.pkt_drop_cnt <= r.pkt_drop_cnt + 1;
                insert_seq_num_error_sh_v(i) := true;
                rin.state <= ST_IDLE;
              end if;
            end if;
      end case;
    end process;

    err_inserter_bus(i).s <= accept(rx_stream_cfg_array(i), false) when r.state = ST_CNT else adapter_ipg_bus(i).s;
    adapter_ipg_bus(i).m <= err_inserter_bus(i).m when r.state = ST_IDLE else transfer_defaults(rx_stream_cfg_array(i));
    feed_back_ipg_s(i) <= feedback_default when r.state = ST_PKT_DROP else feed_back_s(i);

    pkt_checker : nsl_amba.stream_traffic.random_pkt_validator
      generic map (
        mtu_c => mtu_c,
        config_c => rx_stream_cfg_array(i)
        )
      port map (
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        packet_i => adapter_ipg_bus(i).m,
        packet_o => adapter_ipg_bus(i).s,

        stats_o => stats_bus(i).m,
        stats_i => stats_bus(i).s
        );

    stats_bus(i).s <= accept(rx_stream_cfg_array(i), true);

    stats_proc : process(clock_s)
      constant stats_buf_config_v_c : buffer_config_t := buffer_config(rx_stream_cfg_array(i), stats_packed_t'length);
      -- Statistics collection
      variable pkt_size_distribution_v :integer_vector(0 to mtu_c) := (others => 0);
      variable index_data_ko_distribution_v : integer_vector(0 to mtu_c) := (others => 0);
      --
      variable first_error_v : boolean := true;
      variable stats_buf_v : buffer_t := reset(stats_buf_config_v_c);
      variable rx_bytes_v : integer range 0 to 2*mtu_c;
      variable stats_v : stats_t;
      variable tested_pkts_v : integer := 0;
      variable feedback_v : error_feedback_t;
      variable last: boolean;
    begin 
      if reset_n_s = '0' then
        null;
      elsif rising_edge(clock_s) then
        if done_s_tmp(i) /= '1' then
          --
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) then
            rx_bytes_v := rx_bytes_v + byte_count(rx_stream_cfg_array(i), adapter_ipg_bus(i).m);
          end if;
          --
          if insert_seq_num_error_sh_v(i) then
            feedback_v := header_error;
            first_error_v := false;
          else
            if feed_back_ipg_s(i).error = '1' and first_error_v then
              if (feed_back_ipg_s(i).pkt_index_ko < header_packed_t'length) then
                feedback_v := header_error;
              else
                feedback_v := feed_back_ipg_s(i);
              end if;
              first_error_v := false;
            end if;
          end if;
          --
          if is_ready(rx_stream_cfg_array(i), stats_bus(i).s) and is_valid(rx_stream_cfg_array(i), stats_bus(i).m) then
            last := is_last(stats_buf_config_v_c, stats_buf_v);
            stats_buf_v := shift(stats_buf_config_v_c, stats_buf_v, stats_bus(i).m);
            if last then
              stats_v := stats_unpack(bytes(stats_buf_config_v_c, stats_buf_v));
              if not stats_v.payload_valid or not stats_v.header_valid then
                index_data_ko_distribution_v(to_integer(stats_v.index_data_ko)) := 
                  index_data_ko_distribution_v(to_integer(stats_v.index_data_ko)) + 1;
                if feedback_v.pkt_index_ko /= stats_v.index_data_ko then
                  log_info("DUMPED INDEX KO" & " - " & to_string(stats_v, i, tx_stream_cfg_array(i), rx_stream_cfg_array(i)));
                  log_info("DEBUG: feedback_v.pkt_index_ko=" & to_string(feedback_v.pkt_index_ko));
                  assert false severity failure;
                end if;
              else
                log_info("DUMPED EOP OK STATS" & " - " & to_string(stats_v, i, tx_stream_cfg_array(i), rx_stream_cfg_array(i)));
              end if;
            end if;
          end if;
          --
          if is_valid(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) and 
             is_ready(rx_stream_cfg_array(i), adapter_ipg_bus(i).s) and 
             is_last(rx_stream_cfg_array(i), adapter_ipg_bus(i).m) then
              tested_pkts_v := tested_pkts_v + 1;
            pkt_size_distribution_v(rx_bytes_v) := 
                pkt_size_distribution_v(rx_bytes_v) + 1;
            pkt_size_distribution_s(i) <= pkt_size_distribution_v;
            index_data_ko_distribution_s(i) <= index_data_ko_distribution_v;
            first_error_v := true;
            rx_bytes_v := 0;
          end if;
        end if;
      end if;
      if tested_pkts_v = nbr_pkt_to_test then
        done_s_tmp(i) := '1';
      end if;
    end process;
  end generate;

  -- STATISTICS
  final_stats_proc : process(clock_s)
    variable j : integer;
  begin
    if rising_edge(clock_s) then
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
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );
end;
