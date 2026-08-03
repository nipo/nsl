library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_simulation, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_simulation.driver.all;
use nsl_data.prbs.all;
use nsl_data.endian.all;
use nsl_data.text.all;

entity tb is
  generic(
    ddr_mode_c : boolean := false;
    ratio_c : positive := 8;
    left_first_c : boolean := true
    );
end tb;

architecture arch of tb is

  constant serial_period_c : time := 10 ns;
  constant parallel_period_c : time := serial_period_c * ratio_c / if_else(ddr_mode_c, 2, 1);

  constant prbs_init_c : prbs_state(14 downto 0) := (others => '1');

  -- Alignment pattern "00011" - non-repeating at word boundaries for ratio >= 3
  -- Left to right
  constant alignment_pattern_c : std_ulogic_vector(0 to ratio_c-1) := (0 => '1', 1 => '1', others => '0');
  constant start_pattern_c : std_ulogic_vector(0 to ratio_c-1) := (0 => '1', others => '0');
  constant slip_stabilization_count_c: positive := 5;
  constant alignment_words_c : positive := slip_stabilization_count_c * 2 * ratio_c;
  constant prbs_words_c : positive := 64;

  signal parallel_clock_s, serial_clock_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal serial_s : std_ulogic;
  signal parallel_s : std_ulogic_vector(0 to ratio_c-1);
  signal bitslip_s : std_ulogic;
  signal mark_s : std_ulogic;

begin

  dut: nsl_io.serdes.serdes_input
    generic map(
      left_first_c => left_first_c,
      ddr_mode_c => ddr_mode_c,
      from_delay_c => false,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => serial_clock_s,
      parallel_clock_i => parallel_clock_s,
      reset_n_i => reset_n_s,
      serial_i => serial_s,
      parallel_o => parallel_s,
      bitslip_i => bitslip_s,
      mark_o => mark_s
      );

  sender: process
    constant ctxt : log_context := "Send";
    variable prbs_state_v : prbs_state(14 downto 0) := prbs_init_c;
    variable bit_v : std_ulogic;
    variable to_send_v: std_ulogic_vector(0 to ratio_c-1);

    procedure send(word: std_ulogic_vector;
                   lab: string)
    is
      alias xw: std_ulogic_vector(0 to word'length-1) is word;
    begin
      log_info(ctxt, "TX"&lab&" " & to_string(xw));
      for b in xw'range
      loop
        serial_s <= xw(b);
        if ddr_mode_c then
          wait until serial_clock_s'event;
        else
          wait until rising_edge(serial_clock_s);
        end if;
      end loop;
    end procedure;
  begin
    done_s(0) <= '0';
    serial_s <= '0';

    wait until rising_edge(reset_n_s);
    wait for serial_period_c / 4;

    log_info(ctxt, "Sending " & to_string(alignment_words_c) & " alignment words");
    for i in 0 to alignment_words_c - 1
    loop
      send(alignment_pattern_c, "/Alig");
    end loop;

    send(start_pattern_c, "/Sync");

    log_info(ctxt, "Sending " & to_string(prbs_words_c * ratio_c) & " PRBS bits");
    for word in 0 to prbs_words_c - 1
    loop
      to_send_v := prbs_bit_string(prbs_state_v, prbs15, ratio_c);
      prbs_state_v := prbs_forward(prbs_state_v, prbs15, ratio_c);
      send(to_send_v, "/"&to_string(word));
    end loop;

    log_info(ctxt, "Done sending");
    done_s(0) <= '1';
    wait;
  end process;

  receiver: process
    constant ctxt : log_context := "Recv";
    variable prbs_state_v : prbs_state(14 downto 0) := prbs_init_c;
    variable aligned_v : boolean := false;
    variable ignore_count_v : natural := 0;
    variable expected_word_v : std_ulogic_vector(0 to ratio_c-1);
    variable received_word_v : std_ulogic_vector(0 to ratio_c-1);
    variable word_count_v : natural := 0;
    variable words_to_skip_v : natural;
  begin
    done_s(1) <= '0';
    bitslip_s <= '0';

    wait until rising_edge(reset_n_s);
    wait until rising_edge(parallel_clock_s);

    log_info(ctxt, "Expected alignment word: " & to_string(alignment_pattern_c));
    log_info(ctxt, "Aligning...");

    for repeats in 1 to ratio_c*2
    loop
      for stabilize in slip_stabilization_count_c-1 downto 0
      loop
        wait until rising_edge(parallel_clock_s);
        wait for 1 ps;
        bitslip_s <= '0';

        if left_first_c then
          received_word_v := parallel_s;
        else
          received_word_v := bitswap(parallel_s);
        end if;

        if stabilize = 0 then
          log_info(ctxt, "RX/Alig " & to_string(received_word_v));
        else
          log_info(ctxt, "RX/Ignr " & to_string(received_word_v));
        end if;
      end loop;

      if received_word_v = alignment_pattern_c then
        aligned_v := true;
        exit;
      end if;

      log_info(ctxt, "Mismatch, issuing bitslip");
      bitslip_s <= '1';
    end loop;

    assert aligned_v
      report "Alignment failed"
      severity failure;

    log_info(ctxt, "Match, aligned, wait for start");

    loop
      wait until rising_edge(parallel_clock_s);
      wait for 1 ps;

      if left_first_c then
        received_word_v := parallel_s;
      else
        received_word_v := bitswap(parallel_s);
      end if;

      log_info(ctxt, "RX/Strt " & to_string(received_word_v));

      if received_word_v(1) = '0' then
        exit;
      end if;
    end loop;

    log_info(ctxt, "Verifying PRBS words");
    for i in 0 to prbs_words_c - 1
    loop
      wait until rising_edge(parallel_clock_s);
      wait for 1 ps;

      if left_first_c then
        received_word_v := parallel_s;
      else
        received_word_v := bitswap(parallel_s);
      end if;

      log_info(ctxt, "RX#"&to_string(i)&" " & to_string(received_word_v));

      expected_word_v := prbs_bit_string(prbs_state_v, prbs15, ratio_c);
      prbs_state_v := prbs_forward(prbs_state_v, prbs15, ratio_c);

      assert_equal(ctxt, "PRBS word " & to_string(i), received_word_v, expected_word_v, failure);

      word_count_v := word_count_v + 1;
    end loop;

    log_info(ctxt, "Verified " & to_string(word_count_v) & " PRBS words");
    done_s(1) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period => time_vector'(0 => parallel_period_c, 1 => serial_period_c),
      reset_duration(0) => parallel_period_c * 4,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => parallel_clock_s,
      clock_o(1) => serial_clock_s,
      done_i => done_s
      );

end;
