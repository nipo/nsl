library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_amba;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;

entity tb is
end tb;

architecture arch of tb is

  constant nbr_scenario : integer := 3;
  constant min_size_c : positive := 8;
  constant padding_byte_c : byte := x"ff";
  constant config_c : stream_cfg_array_t :=
    (0 => config(1, last => true),
     1 => config(2, last => true),
     2 => config(4, last => true));

  type stream_cfg_array_t is array (natural range <>) of config_t;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to nbr_scenario -1);
  signal in_s, out_s, out_paced_s : bus_vector(0 to nbr_scenario - 1);

begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate
  begin
  gen: process
  begin
    in_s(i).m <= transfer_defaults(config_c(i));
    wait for 95 ns;

    -- Test 1: Frame shorter than min_size (4 bytes < 8)
    -- Expected output: 4 data bytes + 4 padding bytes + commit
    packet_send(cfg => config_c(i),
                clock => clock_s,
                stream_i => in_s(i).s,
                stream_o => in_s(i).m,
                packet => from_hex("01020304"));

    wait for 100 ns;

    -- Test 2: Frame equal to min_size (8 bytes)
    -- Expected output: 8 data bytes + commit (no padding)
    packet_send(cfg => config_c(i),
                clock => clock_s,
                stream_i => in_s(i).s,
                stream_o => in_s(i).m,
                packet => from_hex("0102030405060708"));

    wait for 100 ns;

    -- Test 3: Frame longer than min_size (12 bytes > 8)
    -- Expected output: 12 data bytes + commit (no padding)
    packet_send(cfg => config_c(i),
                clock => clock_s,
                stream_i => in_s(i).s,
                stream_o => in_s(i).m,
                packet => from_hex("0102030405060708090a0b0c"));

    wait for 100 ns;

    -- Test 4: Very short frame (1 byte < 8)
    -- Expected output: 1 data byte + 7 padding bytes + commit
    packet_send(cfg => config_c(i),
                clock => clock_s,
                stream_i => in_s(i).s,
                stream_o => in_s(i).m,
                packet => from_hex("aa"));

    wait for 100 ns;

    -- Test 5: Short frame with cancel status (3 bytes < 8)
    -- Expected output: 3 data bytes + 5 padding bytes
    packet_send(cfg => config_c(i),
                clock => clock_s,
                stream_i => in_s(i).s,
                stream_o => in_s(i).m,
                packet => from_hex("112233"));
    wait;
  end process;

  chk: process
  begin
    done_s(i) <= '0';
    out_paced_s(i).s <= accept(config_c(i), false);
    wait for 100 ns;

    -- Check 1: 4 bytes padded to 8
    log_info("Checking scenario " & to_string(i) & " test 1: expecting 4 data + 4 padding bytes");
    packet_check(cfg => config_c(i),
                   clock => clock_s,
                   stream_i => out_paced_s(i).m,
                   stream_o => out_paced_s(i).s,
                   packet => from_hex("01020304ffffffff"));

    -- Check 2: 8 bytes, no padding
    log_info("Checking scenario " & to_string(i) & " test 2: expecting 8 data bytes, no padding");
    packet_check(cfg => config_c(i),
                 clock => clock_s,
                 stream_i => out_paced_s(i).m,
                 stream_o => out_paced_s(i).s,
                 packet => from_hex("0102030405060708"));

    -- Check 3: 12 bytes, no padding
    log_info("Checking scenario " & to_string(i) & " test 3: expecting 12 data bytes, no padding");
    packet_check(cfg => config_c(i),
                 clock => clock_s,
                 stream_i => out_paced_s(i).m,
                 stream_o => out_paced_s(i).s,
                 packet => from_hex("0102030405060708090a0b0c"));

    -- Check 4: 1 byte padded to 8
    log_info("Checking scenario " & to_string(i) & " test 4: expecting 1 data + 7 padding bytes");
    packet_check(cfg => config_c(i),
                 clock => clock_s,
                 stream_i => out_paced_s(i).m,
                 stream_o => out_paced_s(i).s,
                 packet => from_hex("aaffffffffffffff"));

    -- Check 5: 3 bytes padded to 8 with cancel status
    log_info("Checking scenario " & to_string(i) & " test 5: expecting 3 data + 5 padding bytes");
    packet_check(cfg => config_c(i),
                clock => clock_s,
                stream_i => out_paced_s(i).m,
                stream_o => out_paced_s(i).s,
                packet => from_hex("112233ffffffffff"));

    log_info("Padder tests : " & to_string(i) & " passed.");
    done_s(i) <= '1';
    wait;
  end process;

  dut: nsl_amba.stream_traffic.axi4_stream_padder
    generic map(
      config_c => config_c(i),
      min_size_c => min_size_c,
      padding_byte_c => padding_byte_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => in_s(i).m,
      in_o => in_s(i).s,
      out_o => out_s(i).m,
      out_i => out_s(i).s
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

        in_i => out_s(i).m,
        in_o => out_s(i).s,

        out_o => out_paced_s(i).m,
        out_i => out_paced_s(i).s
    );
  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );
end;
