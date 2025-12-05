library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;
use nsl_data.prbs.all;

entity tb is
end tb;

architecture arch of tb is

  constant nbr_scenario : integer := 3;
  constant config_c : stream_cfg_array_t :=
    (0 => config(4, last => true),
     1 => config(2, last => true),
     2 => config(4, last => true));

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario - 1);

  constant cfg_c: config_t := config(4, last => true);

  constant crc_c : crc_params_t := crc_params(
    init             => "",
    poly             => x"104c11db7",
    complement_input => false,
    complement_state => true,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );
  
  function packet_data_with_crc(crc_param: crc_params_t; data : byte_string) return byte_string
  is
    constant s : crc_state_t := crc_update(crc_param,
                                           crc_init(crc_param),
                                           data);
  begin
    return data & crc_spill(crc_param, s);
  end function;

begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate
    signal input_s, output_s, output_paced_s : bus_t;
    shared variable master_q, slave_q : frame_queue_root_t;
  begin
    ge_chk_proc: process
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
      variable frame_byte_count: integer;
      variable nbr_pkt_played_v : integer := 0;
    begin
      done_s(i) <= '0';
      frame_queue_init(master_q);
      frame_queue_init(slave_q);

      wait for 100 ns;

      log_info("INFO: scenario " & to_string(i) & " Playing...");
      for stream_beat_count in 1 to 128
      loop
        frame_byte_count := stream_beat_count * config_c(i).data_width;

        frame_queue_check_io(root_master => master_q, 
                            root_slave  => slave_q, 
                            data1 => prbs_byte_string(state_v, prbs31, frame_byte_count),
                            data2 => packet_data_with_crc(crc_c, prbs_byte_string(state_v, prbs31, frame_byte_count)));

        state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);

        nbr_pkt_played_v := nbr_pkt_played_v + 1;
      end loop;

      log_info("INFO: scenario "& to_string(i) & " number of packets played  : " & to_string(nbr_pkt_played_v));
      done_s(i) <= '1';
      wait;

    end process;

      -- dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
      -- generic map(
      --   config_c => config_c(i),
      --   prefix_c => "IN SCENARIO " & to_string(i)
      --   )
      -- port map(
      --   clock_i => clock_s,
      --   reset_n_i => reset_n_s,

      --   bus_i => input_s
      --   );

    -- dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    --   generic map(
    --     config_c => config_c(i),
    --     prefix_c => "OUT SCENARIO " & to_string(i)
    --     )
    --   port map(
    --     clock_i => clock_s,
    --     reset_n_i => reset_n_s,

    --     bus_i => output_paced_s
    --     );
    
    dut: nsl_amba.stream_crc.axi4_stream_crc_adder
      generic map(
        config_c => config_c(i),
        crc_c => crc_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => input_s.m,
        in_o => input_s.s,

        out_o => output_s.m,
        out_i => output_s.s
        );

    pkt_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
    generic map(
        config_c               => config_c(i),
        probability_denom_l2_c => 30,
        probability_c          => 0.1
    )
    port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        in_i => output_s.m,
        in_o => output_s.s,

        out_o => output_paced_s.m,
        out_i => output_paced_s.s
    );
      
    master_proc: process is
    begin
      input_s.m <= transfer_defaults(config_c(i));
      wait for 40 ns;
      frame_queue_master(config_c(i), master_q, clock_s, input_s.s, input_s.m, timeout => 1000 us);
    end process;
      
    slave_proc: process is
    begin
      output_paced_s.s <= accept(config_c(i), false);
      wait for 40 ns;
      frame_queue_slave(config_c(i), slave_q, clock_s, output_paced_s.m, output_paced_s.s);
    end process;
  end generate;
  
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
