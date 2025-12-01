library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_mii, nsl_data, nsl_amba, nsl_logic;
use nsl_simulation.logging.all;
use nsl_mii.rgmii.all;
use nsl_mii.link.all;
use nsl_mii.mii.all;
use nsl_mii.flit.all;
use nsl_mii.testing.all;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_data.text.all;
use nsl_amba.stream_traffic.all;

architecture arch of tb is
  constant nbr_scenario : integer := 3;
  constant config_c : stream_cfg_array_t :=
   (0 => axi4_flit_cfg,
    1 => config(2, user => 1,  last => true),
    2 => config(4, user => 1, last => true));

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario - 1);

begin
  gen_scenarios : for i in 0 to nbr_scenario-1 generate
    shared variable in_axi_q, out_axi_q : frame_queue_root_t;
    signal user_flip_s: boolean := false;
    signal user_flip_beat_s : integer := 0;
    signal in_s, out_s, out_paced_s : bus_t;
    signal in_error_s : std_ulogic;  
  begin 
    gen_stimuli_proc : process 
      
      variable rx_packet_v : byte_string(0 to 4-1);
      variable rx_user_v : byte_string(0 to 4-1);
      variable rx_id_v : std_ulogic_vector(config_c(i).id_width-1 downto 0);
      variable rx_dest_v : std_ulogic_vector(config_c(i).dest_width-1 downto 0);

    begin
      done_s(i) <= '0';
      frame_queue_init(in_axi_q);
      frame_queue_init(out_axi_q);

      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);

      -- Test 1: Normal packet without errors
      log_info("===== Scenario : " & to_string(i) & " Test 1: Normal packet (should pass through) =====");
      send_and_check_packet(clock_s, in_axi_q, out_axi_q, user_flip_s, user_flip_beat_s, data => from_hex("01234567"));
      
      -- Test 2: Packet with error in middle byte (beat 3)
      log_info("===== Scenario : " & to_string(i) & " Test 2: Packet with error at beat 3 (should be dropped) =====");
      send_packet_with_error(
        clock_s, 
        in_axi_q,
        user_flip_s, 
        user_flip_beat_s,
        data => from_hex("0101010101010101010101010101"),
        error_beat => 3);
      
      -- Test 3: Normal packet to verify filter is working after error
      log_info("===== Scenario : " & to_string(i) & " Test 3: Normal packet after error (should pass through) =====");
      send_and_check_packet(clock_s, in_axi_q, out_axi_q, user_flip_s, user_flip_beat_s, data => from_hex("01234567"));
      
      -- Test 4: Error in last byte (beat 6 of 7-byte packet)
      log_info("===== Scenario : " & to_string(i) & " Test 4: Error in last byte (should be dropped) =====");
      send_packet_with_error(
        clock_s, 
        in_axi_q,
        user_flip_s, 
        user_flip_beat_s,
        data => from_hex("0101010101010101"),
        error_beat => from_hex("0101010101010101")'length/config_c(i).data_width - 1);
      
      -- Test 5: Error in first byte (beat 0)
      log_info("===== Scenario : " & to_string(i) & " Test 5: Error in first byte (should be dropped) =====");
      send_packet_with_error(
        clock_s, 
        in_axi_q,
        user_flip_s, 
        user_flip_beat_s,
        data => from_hex("a0a0a0a0a0a0"),
        error_beat => 0);
      
      -- Test 6: Verify previous error packets were not output
      log_info("===== Scenario : " & to_string(i) & " Test 6: Normal packet to verify errors were filtered =====");
      send_and_check_packet(clock_s, in_axi_q, out_axi_q, user_flip_s, user_flip_beat_s, data => from_hex("55555555555555555555555555555555"));
      
      -- Final normal packet
      log_info("===== Scenario : " & to_string(i) & " Test 8: Final normal packet =====");
      send_and_check_packet(clock_s, in_axi_q, out_axi_q, user_flip_s, user_flip_beat_s, data => from_hex("cafebabe"));

      log_info("===== All tests from scenario " & to_string(i) & " completed successfully =====");
      done_s(i) <= '1';
      wait;
    end process;

    in_error_s <= user(config_c(i), in_s.m)(0);

    dut: nsl_amba.stream_fifo.axi4_stream_fifo_clean
      generic map (
        config_c => config_c(i)
      )
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        in_i => in_s.m,
        in_error_i => in_error_s,
        in_o => in_s.s,

        out_o => out_s.m,
        out_i => out_s.s
        );

    pkt_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
    generic map(
        config_c               => config_c(i),
        probability_denom_l2_c => 30,
        probability_c          => 0.2
    )
    port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        in_i => out_s.m,
        in_o => out_s.s,

        out_o => out_paced_s.m,
        out_i => out_paced_s.s
    );

    axi_master: process is
    begin
      in_s.m <= transfer_defaults(config_c(i));
      wait for 40 ns;
      if in_axi_q.head /= null then
        frame_queue_master(config_c(i), user_flip_s, user_flip_beat_s, in_axi_q, clock_s, in_s.s, in_s.m, timeout => 10000 us);
      end if;
    end process;

    flit_slave: process is
    begin
      out_paced_s.s <= accept(config_c(i), false);
      wait for 40 ns;
      frame_queue_slave(cfg => config_c(i), 
                        root => out_axi_q, 
                        clock => clock_s, 
                        stream_i => out_paced_s.m,
                        stream_o => out_paced_s.s);
    end process;
    
    axi_stream_in_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        config_c => config_c(i),
        prefix_c => "AXI-STREAM-IN"
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        bus_i.m => in_s.m,
        bus_i.s => in_s.s
        );

    axi_stream_out_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        config_c => config_c(i),
        prefix_c => "AXI-STREAM-OUT"
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        bus_i.m => out_paced_s.m,
        bus_i.s => out_paced_s.s
        );

  end generate;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 14 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
