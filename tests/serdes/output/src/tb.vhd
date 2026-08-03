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

  constant prbs_init_c : prbs_state(14 downto 0) := "101" & x"555";

  constant null_word_c : std_ulogic_vector(0 to ratio_c-1) := (others => '0');
  -- Make the 1 appear on right using descending.
  constant sync_word_c : std_ulogic_vector(ratio_c-1 downto 0) := (0 => '1', others => '0');
  constant alignment_words_c : positive := ratio_c  * 4;
  constant prbs_words_c : positive := 64;

  signal parallel_clock_s, serial_clock_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal parallel_s : std_ulogic_vector(0 to ratio_c-1);
  signal serial_s : std_ulogic;

begin

  dut: nsl_io.serdes.serdes_output
    generic map(
      left_first_c => left_first_c,
      ddr_mode_c => ddr_mode_c,
      to_delay_c => false,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => serial_clock_s,
      parallel_clock_i => parallel_clock_s,
      reset_n_i => reset_n_s,
      parallel_i => parallel_s,
      serial_o => serial_s
      );

  sender: process
    constant ctxt : log_context := "Send";
    variable prbs_state_v : prbs_state(14 downto 0) := prbs_init_c;
    variable word_v : std_ulogic_vector(0 to ratio_c-1);

    procedure send(word: std_ulogic_vector;
                   ctx: string)
    is
    begin
      log_info(ctxt, "TX"&ctx&" "&to_string(word));
      wait until falling_edge(parallel_clock_s);
      if left_first_c then
        parallel_s <= word;
      else
        parallel_s <= bitswap(word);
      end if;
      wait until rising_edge(parallel_clock_s);
    end procedure;

  begin
    done_s(0) <= '0';
    parallel_s <= (others => '0');

    wait until rising_edge(reset_n_s);
    wait until rising_edge(parallel_clock_s);

    log_info(ctxt, "Sending " & to_string(alignment_words_c - 1) & " alignment zeros");

    for i in 1 to alignment_words_c - 1
    loop
      send(null_word_c, "/algn");
    end loop;

    log_info(ctxt, "Sending marker word");
    send(sync_word_c, "/mark");

    log_info(ctxt, "Sending " & to_string(prbs_words_c) & " PRBS words");
    for i in 0 to prbs_words_c - 1
    loop
      word_v := prbs_bit_string(prbs_state_v, prbs15, ratio_c);
      prbs_state_v := prbs_forward(prbs_state_v, prbs15, ratio_c);
      send(word_v, "#"&to_string(i));
    end loop;

    log_info(ctxt, "Done sending");
    done_s(0) <= '1';
    wait;
  end process;

  receiver: process
    constant ctxt : log_context := "Recv";
    variable prbs_state_v : prbs_state(14 downto 0) := prbs_init_c;
    variable zeros_seen_v : natural := 0;
    variable aligned_v : boolean := false;
    variable bit_v : std_ulogic;
    variable word_v, expected_v : std_ulogic_vector(0 to ratio_c-1);
    variable bit_count_v : natural := 0;

    procedure rx(variable b: out std_ulogic)
    is
    begin
      if ddr_mode_c then
        if serial_clock_s = '1' then
          wait until falling_edge(serial_clock_s);
        else
          wait until rising_edge(serial_clock_s);
        end if;
      else
        wait until rising_edge(serial_clock_s);
      end if;
      wait for 2 ps;

      b := serial_s;
    end procedure;

    procedure word_rx(variable w: out std_ulogic_vector)
    is
      alias xw: std_ulogic_vector(0 to w'length-1) is w;
    begin
      for i in xw'range
      loop
        rx(xw(i));
      end loop;
    end procedure;
      
  begin
    done_s(1) <= '0';

    wait until rising_edge(reset_n_s);
    wait for serial_period_c / 4;

    log_info(ctxt, "Waiting for alignment");

    while not aligned_v
    loop
      rx(bit_v);
      bit_v := serial_s;
      if bit_v = '0' then
        zeros_seen_v := zeros_seen_v + 1;
      elsif zeros_seen_v >= (alignment_words_c / 2) * ratio_c then
        log_info(ctxt, "Aligned after " & to_string(zeros_seen_v) & " zeros");
        aligned_v := true;
      else
        zeros_seen_v := 0;
      end if;
    end loop;

    log_info(ctxt, "Verifying PRBS bits");
    for i in 0 to prbs_words_c - 1
    loop
      expected_v := prbs_bit_string(prbs_state_v, prbs15, ratio_c);
      word_rx(word_v);
      log_info(ctxt, "RX#"&to_string(i)&" "&to_string(word_v));
      if word_v /= expected_v then
        wait for serial_period_c * ratio_c * 2;
      end if;
      assert_equal(ctxt, "RX#"&to_string(i), word_v, expected_v, failure);
      prbs_state_v := prbs_forward(prbs_state_v, prbs15, ratio_c);
    end loop;

    log_info(ctxt, "Verified " & to_string(bit_count_v) & " PRBS bits");
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
