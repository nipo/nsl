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
    scenario_c : natural := 0
  );
end tb;

architecture arch of tb is

  type stream_cfg_array_t is array (natural range <>) of config_t;

  constant tx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(2, keep => true, last => true),
     1 => config(2, keep => true, last => true),
     2 => config(4, keep => true, last => true));

  constant rx_stream_cfg_array : stream_cfg_array_t := 
    (0 => config(2, keep => true, last => true),
     1 => config(2, keep => true, last => true),
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

    signal clock_i_s : std_ulogic;
    signal reset_n_i_s : std_ulogic;
    signal done_s : std_ulogic_vector(0 to 0);

    signal cmd_bus, tx_bus,rx_bus,stats_bus,asserter_bus : bus_t;
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

  pkt_checker : nsl_amba.random_pkt_checker.random_pkt_validator
    generic map (
      mtu_c => mtu_c,
      config_c => tx_stream_cfg_array(scenario_c),
      data_prbs_poly => prbs31,
      header_crc_params_c => header_crc_params
      )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
      --
      in_i => tx_bus.m,
      in_o => tx_bus.s,
      --
      out_o => stats_bus.m,
      out_i => stats_bus.s
      );

  stats_asserter : nsl_amba.random_pkt_checker.random_stats_asserter
    generic map (
      mtu_c => mtu_c,
      config_c => tx_stream_cfg_array(scenario_c)
      )
    port map (
      clock_i => clock_i_s,
      reset_n_i => reset_n_i_s,
      --
      in_i => stats_bus.m,
      in_o => stats_bus.s,
      --
      out_o => asserter_bus.m,
      out_i => asserter_bus.s
      );

  dumper_axi_from_sie: nsl_amba.axi4_stream.axi4_stream_dumper
  generic map(
    config_c => rx_stream_cfg_array(scenario_c),
    prefix_c => "ASSERTER_OUT"
    )
  port map(
    clock_i => clock_i_s,
    reset_n_i => reset_n_i_s,

    bus_i => asserter_bus
    );

    asserter_bus.s <= accept(tx_stream_cfg_array(scenario_c), true);

  stats_proc : process
  begin 
    done_s <= (others => '0');
    wait until is_last(tx_stream_cfg_array(scenario_c), tx_bus.m) and is_valid(tx_stream_cfg_array(scenario_c), tx_bus.m);
    wait for 1000 ns;
    done_s <= (others => '1');
    wait;
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
