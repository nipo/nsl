library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_digilent, nsl_sipeed, nsl_clocking, nsl_amba, nsl_data, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_amba.random_pkt_checker.all;
use nsl_data.prbs.all;
use nsl_data.crc.all;
use nsl_data.bytestream.all;

entity boundary is
  port (
    clk_i: in std_logic;
    j4_io: inout nsl_digilent.pmod.pmod_double_t;
    j5_io: inout nsl_digilent.pmod.pmod_double_t;
    s_i: in std_logic_vector(1 to 2)
  );
end boundary;

architecture arch of boundary is

  constant mtu_c : integer := 50;
  constant probability_denom_l2_c : integer range 1 to 31 := 31;
  constant probability_c : real := 0.001;
  constant mode_c : string(1 to 6) := "RANDOM";
  constant inter_pkt_gap_size : integer := 100;
  constant pkt_disappearance_rate : integer := 64;
  constant pkt_disappearance_rate_l2 : integer := nsl_math.arith.log2(pkt_disappearance_rate);
  constant tx_stream_cfg : config_t := config(4, keep => true, last => true);
  constant rx_stream_cfg : config_t := config(2, keep => true, last => true);
  constant pressed_button_delay : integer := 25000000; -- 0.5 sec delay for 50MHz clock
  constant stats_buf_config_c : buffer_config_t := buffer_config(rx_stream_cfg, STATS_SIZE);
  constant feedback_default : error_feedback_t := (error => '0',
                                                   pkt_index_ko => to_unsigned(0, 16));

  type state_t is (
    ST_IDLE,
    ST_CNT,
    ST_PKT_DROP
    );

  type error_state_t is (
    ST_ERROR_IDLE,
    ST_ERROR_INCR,
    ST_ERROR_ASSERT
    );

  type button_stats_t is (
    BUTTON_STATE_IDLE,
    BUTTON_STATE_INSERT_INDEX_ERR,
    BUTTON_STATE_PRINT_INSERTED_ERR,
    BUTTON_STATE_PRINT_DROPPED_PKTS
    );
      
  constant blink_time: integer := 25000000;
  signal cnt: integer := 0;
  signal led_state: std_ulogic := '0';
  signal insert_error_s : boolean := false;
  signal byte_index_s : integer range 0 to rx_stream_cfg.data_width;
  signal feed_back_s, feed_back_ipg_s : error_feedback_t;

  signal cmd_bus, tx_bus , stats_bus, adapter_bus, adapter_inter_pkt_gap_bus, err_inserter_bus, pkt_validator_rand_back_pressure_bus, adapter_ipg_bus, debug_bus  : bus_t;

  signal clock_s, reset_n_s: std_ulogic;
  signal pressed_s: std_ulogic_vector(s_i'range);

  type regs_t is
    record
      button_state : button_stats_t;
      pressed_button_delay_cnt : integer range 0 to pressed_button_delay; 
      button_pressed1, button_pressed2 : std_ulogic;
      stats_report_cnt : unsigned(7 downto 0);
      injected_error_cnt : unsigned(7 downto 0);
      ipg_cnt : integer range 0 to inter_pkt_gap_size + 1;
      pkt_cnt : unsigned(pkt_disappearance_rate_l2 downto 0);
      tb_error: unsigned(7 downto 0);
      state : state_t;
      incr_state : error_state_t;
      rx_bytes, rx_bytes_r : integer range 0 to 2*mtu_c;
      seq_num : unsigned(15 downto 0);
      stats_buf : buffer_t;
      -- DEBUG
      seq_num_ko_debug : boolean;
      stats_debug, stats_debug_r : stats_t;
      nbr_err_inserted_debug : unsigned(15 downto 0);
    end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.button_state <= BUTTON_STATE_IDLE;
      r.pressed_button_delay_cnt <= 0;
      r.button_pressed1 <= '0';
      r.button_pressed2 <= '0';
      r.stats_report_cnt <= (others => '0');
      r.injected_error_cnt <= (others => '0');
      r.ipg_cnt <=  0;
      r.pkt_cnt <=  (others => '0');
      r.tb_error <= x"00";
      r.state <=  ST_IDLE;
      r.incr_state <=  ST_ERROR_IDLE;
      r.rx_bytes <=  0;
      r.rx_bytes_r <=  0;
      r.seq_num <=  (others => '0');
      r.stats_buf <= reset(stats_buf_config_c);
      r.seq_num_ko_debug <= true;
      r.nbr_err_inserted_debug <= (others => ('0'));
    end if;
  end process;

  clk_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  cmd_gen : nsl_amba.random_pkt_checker.random_cmd_generator
    generic map (
      mtu_c => mtu_c,
      config_c => tx_stream_cfg,
      min_pkt_size => 2
      )
    port map (
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      --
      enable_i => '1',
      --      
      out_o => cmd_bus.m,
      out_i => cmd_bus.s
      );

  pkt_gen : nsl_amba.random_pkt_checker.random_pkt_generator
    generic map (
      mtu_c => mtu_c,
      config_c => tx_stream_cfg,
      data_prbs_init_c => x"deadbee"&"111",
      data_prbs_poly_c => prbs31
      )
    port map (
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      --
      in_i => cmd_bus.m,
      in_o => cmd_bus.s,
      --
      out_o => tx_bus.m,
      out_i => tx_bus.s
      );

  axi4_stream_medium_width_adapter : nsl_amba.axi4_stream.axi4_stream_width_adapter
    generic map (
      in_config_c => tx_stream_cfg,
      out_config_c => rx_stream_cfg
    )
    port map (
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => tx_bus.m,
      in_o => tx_bus.s,

      out_o => adapter_bus.m,
      out_i => adapter_bus.s
    );

  error_inserter : nsl_amba.axi4_stream.axi4_stream_error_inserter
    generic map (
      config_c => rx_stream_cfg,
      probability_denom_l2_c => probability_denom_l2_c,
      probability_c => probability_c,
      mode_c => mode_c,
      mtu_c => mtu_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      insert_error_i => insert_error_s,
      byte_index_i => byte_index_s,

      in_i => adapter_bus.m,
      in_o => adapter_bus.s,

      out_o => err_inserter_bus.m,
      out_i => err_inserter_bus.s,
      feed_back_o => feed_back_s
      );

  inter_pkt_gap_proc : process(r, err_inserter_bus, stats_bus, feed_back_ipg_s, adapter_ipg_bus)
    variable stats_v : stats_t;
  begin
    rin <= r;

    stats_v := stats_unpack(bytes(stats_buf_config_c, shift(stats_buf_config_c, r.stats_buf, stats_bus.m)));

    if is_valid(rx_stream_cfg, adapter_ipg_bus.m) and is_ready(rx_stream_cfg, adapter_ipg_bus.s) then
      rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(rx_stream_cfg, adapter_ipg_bus.m));
      if is_last(rx_stream_cfg, adapter_ipg_bus.m) then
        rin.rx_bytes_r <= r.rx_bytes + count_valid_bytes(keep(rx_stream_cfg, adapter_ipg_bus.m));
        rin.rx_bytes <= 0;
      end if;
    end if;

    if feed_back_ipg_s.error = '1' and is_ready(rx_stream_cfg, err_inserter_bus.s) then
      rin.nbr_err_inserted_debug <= r.nbr_err_inserted_debug + 1;
    end if;

    if is_valid(rx_stream_cfg, err_inserter_bus.m) and is_ready(rx_stream_cfg, err_inserter_bus.s) then
      if is_last(rx_stream_cfg, adapter_ipg_bus.m) then
        rin.seq_num <= r.seq_num + 1;
      end if;
    end if;

    if is_ready(rx_stream_cfg, stats_bus.s) and is_valid(rx_stream_cfg, stats_bus.m) then
      rin.stats_buf <= shift(stats_buf_config_c, r.stats_buf, stats_bus.m);
      if is_last(rx_stream_cfg, stats_bus.m) then-- is_last(stats_buf_config_c, r.stats_buf) then
        if not stats_v.stats_payload_valid or not stats_v.stats_header_valid then
          rin.stats_report_cnt <= r.stats_report_cnt + 1;
          rin.stats_debug_r <= r.stats_debug;
          rin.stats_debug <= stats_v;
          
        end if;
      end if;
    end if;

    case r.incr_state is
      when ST_ERROR_IDLE =>
        if feed_back_ipg_s.error = '1' or r.state = ST_PKT_DROP then
          rin.incr_state <= ST_ERROR_INCR;
        end if;
        --
        if is_valid(rx_stream_cfg, adapter_ipg_bus.m) and is_ready(rx_stream_cfg, adapter_ipg_bus.s) then
          if is_last(rx_stream_cfg, adapter_ipg_bus.m) then
            if (r.rx_bytes_r < 2 and (r.seq_num > 255)) then
              if r.rx_bytes + count_valid_bytes(keep(rx_stream_cfg, adapter_ipg_bus.m)) /= 1 then
                rin.incr_state <= ST_ERROR_INCR;
              end if;
            end if;
          end if;
        end if;

      when ST_ERROR_INCR => 
        if is_ready(rx_stream_cfg, stats_bus.s) and is_valid(rx_stream_cfg, stats_bus.m) then
          if is_last(rx_stream_cfg, stats_bus.m) then
            rin.injected_error_cnt <= r.injected_error_cnt + 1;
            rin.incr_state <= ST_ERROR_ASSERT;
          end if;
        end if;

      when ST_ERROR_ASSERT => 
        if r.stats_report_cnt /= r.injected_error_cnt then
           rin.tb_error <= r.tb_error + 1;
        end if;
        rin.incr_state <= ST_ERROR_IDLE;

    end case;

    case r.state is
      when ST_IDLE => 
          if is_valid(rx_stream_cfg, err_inserter_bus.m) and is_ready(rx_stream_cfg, err_inserter_bus.s) then
            if is_last(rx_stream_cfg, err_inserter_bus.m) then
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
          if is_valid(rx_stream_cfg, err_inserter_bus.m) and is_ready(rx_stream_cfg, err_inserter_bus.s) then
            if is_last(rx_stream_cfg, err_inserter_bus.m) then
              rin.state <= ST_IDLE;
            end if;
          end if;
    end case;
  end process;

  err_inserter_bus.s <= accept(rx_stream_cfg, false) when r.state = ST_CNT else adapter_ipg_bus.s;
  adapter_ipg_bus.m <= err_inserter_bus.m when r.state = ST_IDLE else transfer_defaults(rx_stream_cfg);
  feed_back_ipg_s <= feedback_default when r.state = ST_PKT_DROP else feed_back_s;

  pkt_checker : nsl_amba.random_pkt_checker.random_pkt_validator
    generic map (
      mtu_c => mtu_c,
      config_c => rx_stream_cfg,
      data_prbs_poly_c => prbs31
      )
    port map (
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      --
      in_i => adapter_ipg_bus.m,
      in_o => adapter_ipg_bus.s,
      --
      out_o => stats_bus.m,
      out_i => stats_bus.s
      );

  stats_bus.s <= accept(rx_stream_cfg, true);

  deglitchers: for i in s_i'range
    generate
      ai: nsl_clocking.async.async_input
        generic map(
          debounce_count_c => 10_000
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,
          data_i => s_i(i),
          falling_o => pressed_s(i)
          );
    end generate;

  ss: nsl_sipeed.pmod_dtx2.pmod_dtx2_hex
    generic map(
      clock_i_hz_c => 50_000_000
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      value_i => r.tb_error,
      pmod_io => j4_io
      );

  led: nsl_sipeed.pmod_8xled.pmod_8xled_driver
    port map(
      led_i => std_ulogic_vector(r.tb_error),
      pmod_io => j5_io
     );
  
end arch;
