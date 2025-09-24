library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_digilent, nsl_sipeed, nsl_clocking, nsl_amba, nsl_data;
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

  constant mtu_c : integer := 1500;
  constant probability_denom_l2_c : integer range 1 to 31 := 31;
  constant probability_c : real := 0.00000001;
  constant mode_c : string(1 to 6) := "RANDOM";
  constant inter_pkt_gap_size : natural := 50;

  constant stats_printer_bus : config_t := (config(8, keep => true, last => true));
  constant tx_stream_cfg : config_t := config(1, keep => true, last => true);
  constant rx_stream_cfg : config_t := config(1, keep => true, last => true);

  constant header_crc_params : crc_params_t := crc_params(
    init             => "",
    poly             => x"18005",
    complement_input => false,
    complement_state => false,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );
    
  type state_t is (
    ST_IDLE,
    ST_CNT
    );

  constant blink_time: integer := 25000000;
  signal cnt: integer := 0;
  signal led_state: std_ulogic := '0';
  signal state_s : state_t;
  signal insert_error_s : boolean := false;
  signal byte_index_s : integer range 0 to rx_stream_cfg.data_width;
  signal feed_back_s : error_feedback_t;

  signal cmd_bus, tx_bus , stats_bus, adapter_bus, adapter_inter_pkt_gap_bus, err_inserter_bus, stats_adpater_bus, asserter_back_pressure_bus, pkt_validator_rand_back_pressure_bus  : bus_t;

  signal clock_s, reset_n_s: std_ulogic;
  signal pressed_s: std_ulogic_vector(s_i'range);

  type regs_t is
  record
    counter: unsigned(7 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin

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
      config_c => tx_stream_cfg
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
      data_prbs_init => x"deadbee"&"111",
      data_prbs_poly => prbs31,
      header_crc_params_c => header_crc_params
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

  inter_pkt_gap_proc : process(clock_s, reset_n_s)
    variable inter_pkt_gap_cnt_v : natural := 0;
  begin
    if reset_n_s = '0' then
      state_s <= ST_IDLE;
    elsif rising_edge(clock_s) then
      case state_s is
        when ST_IDLE => 
          if is_valid(rx_stream_cfg, adapter_bus.m) and is_ready(rx_stream_cfg, adapter_bus.s) then
            if is_last(rx_stream_cfg, adapter_bus.m) then
              state_s <= ST_CNT;
            end if;
          end if;
          when ST_CNT =>
            inter_pkt_gap_cnt_v := inter_pkt_gap_cnt_v + 1;
            if inter_pkt_gap_cnt_v >= inter_pkt_gap_size then
              inter_pkt_gap_cnt_v := 0;
              state_s <= ST_IDLE;
            end if;
      end case;
    end if;
  end process;

  adapter_bus.s <= accept(rx_stream_cfg, false) when state_s = ST_CNT else adapter_inter_pkt_gap_bus.s;
  adapter_inter_pkt_gap_bus.m <= adapter_bus.m when state_s = ST_IDLE else transfer_defaults(rx_stream_cfg);

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

      in_i => adapter_inter_pkt_gap_bus.m,
      in_o => adapter_inter_pkt_gap_bus.s,

      out_o => err_inserter_bus.m,
      out_i => err_inserter_bus.s,

      feed_back_o => feed_back_s
      );

  pkt_checker : nsl_amba.random_pkt_checker.random_pkt_validator
    generic map (
      mtu_c => mtu_c,
      config_c => rx_stream_cfg,
      data_prbs_poly => prbs31,
      header_crc_params_c => header_crc_params
      )
    port map (
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      --
      in_i => err_inserter_bus.m,
      in_o => err_inserter_bus.s,
      --
      out_o => stats_bus.m,
      out_i => stats_bus.s
      );

  -- stats_bus.s <= accept(rx_stream_cfg, true);
  pkt_validator_rand_back_pressure: nsl_amba.axi4_stream.axi4_stream_pacer
    generic map(
      config_c => rx_stream_cfg,
      probability_c => 0.55
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => stats_bus.m,
      in_o => stats_bus.s,
      
      out_o => pkt_validator_rand_back_pressure_bus.m,
      out_i => pkt_validator_rand_back_pressure_bus.s
      );

  axi4_stream_stats_width_adapter : nsl_amba.axi4_stream.axi4_stream_width_adapter
    generic map (
      in_config_c => rx_stream_cfg,
      out_config_c => stats_printer_bus
    )
    port map (
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => pkt_validator_rand_back_pressure_bus.m,
      in_o => pkt_validator_rand_back_pressure_bus.s,

      out_o => stats_adpater_bus.m,
      out_i => stats_adpater_bus.s
    );

  stats_adpater_bus.s <= accept(stats_printer_bus, true);

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.counter <= x"00";
    end if;
  end process;

  transition: process(r, pressed_s, feed_back_s, stats_adpater_bus, err_inserter_bus, stats_bus, cmd_bus, tx_bus, adapter_bus, adapter_inter_pkt_gap_bus, err_inserter_bus) is
    variable err_trigger_v : boolean := false;
  begin
    rin <= r;

    -- err_trigger_v := is_ready(rx_stream_cfg, stats_bus.s) and is_valid(rx_stream_cfg, stats_bus.m) and is_last(rx_stream_cfg, stats_bus.m);
    err_trigger_v := (feed_back_s.error = '1') and is_ready(rx_stream_cfg, err_inserter_bus.s); 
    -- err_trigger_v := is_ready(stats_printer_bus, err_inserter_bus.s) and is_valid(stats_printer_bus, err_inserter_bus.m) and is_last(stats_printer_bus, err_inserter_bus.m);


    if err_trigger_v then
      rin.counter <= r.counter + 1;
    end if;

    -- if pressed_s(1) = '1' then
    --   rin.counter <= r.counter - 1;
    -- end if;

    -- if pressed_s(2) = '1' then
    --   rin.counter <= r.counter + 1;
    -- end if;
  end process;

  ss: nsl_sipeed.pmod_dtx2.pmod_dtx2_hex
    generic map(
      clock_i_hz_c => 50_000_000
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      value_i => r.counter,
      pmod_io => j4_io
      );

  led: nsl_sipeed.pmod_8xled.pmod_8xled_driver
    port map(
      led_i => std_ulogic_vector(r.counter),
      pmod_io => j5_io
     );
  
end arch;
