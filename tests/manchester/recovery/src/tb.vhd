library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_line_coding, nsl_simulation, nsl_data;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_data.text.all;

architecture arch of tb is

  type natural_vector is array (natural range <>) of natural;

  constant config_count_c : natural := 2;
  constant clock_hz_c : natural_vector(0 to config_count_c-1) := (120000000, 80000000);
  -- Line rate skew, in percent, used for the degraded line scenario.
  constant skew_c : natural_vector(0 to config_count_c-1) := (101, 99);
  constant signal_hz_c : natural := 10000000;

  constant bit_time_c : time := 1 sec / signal_hz_c;
  constant capture_max_c : natural := 64;

  -- 802.3-style preamble, transmitted first, then payload.
  constant preamble_c : std_ulogic_vector(0 to 15) := "1010101010101010";
  constant payload_a_c : std_ulogic_vector(0 to 23) := "110010001111000010110100";
  constant payload_b_c : std_ulogic_vector(0 to 19) := "11111000001010110011";

  constant burst_a_c : std_ulogic_vector(0 to preamble_c'length + payload_a_c'length - 1)
    := preamble_c & payload_a_c;
  constant burst_b_c : std_ulogic_vector(0 to preamble_c'length + payload_b_c'length - 1)
    := preamble_c & payload_b_c;

  signal clock_s, reset_n_s, done_s, fail_s : std_ulogic_vector(0 to config_count_c-1);

begin

  configs: for i in 0 to config_count_c-1 generate
    constant period_c : time := 1 sec / clock_hz_c(i);
    constant half_bit_skewed_c : time := (1 sec / (2 * signal_hz_c)) * skew_c(i) / 100;
    constant name_c : string := "clock " & to_string(clock_hz_c(i) / 1000000) & "MHz";

    signal tx_ready_s, tx_valid_s, tx_bit_s, tx_active_s, tx_data_s : std_ulogic;
    signal invert_s, degraded_sel_s, degraded_s, line_s : std_ulogic;
    signal rx_bit_s, rx_valid_s, rx_active_s : std_ulogic;
    signal rx_captured_s : std_ulogic_vector(0 to capture_max_c-1);
    signal rx_count_s : natural;
  begin

    clock_gen: process is
    begin
      clock_s(i) <= '0';
      wait for period_c / 2;
      clock_s(i) <= '1';
      wait for period_c / 2;
    end process;

    reset_gen: process is
    begin
      reset_n_s(i) <= '0';
      wait for 10 * period_c;
      reset_n_s(i) <= '1';
      wait;
    end process;

    tx: nsl_line_coding.manchester.manchester_transmitter
      generic map(
        clock_i_hz_c => clock_hz_c(i),
        signal_hz_c => signal_hz_c
        )
      port map(
        clock_i => clock_s(i),
        reset_n_i => reset_n_s(i),
        ready_o => tx_ready_s,
        valid_i => tx_valid_s,
        bit_i => tx_bit_s,
        active_o => tx_active_s,
        data_o => tx_data_s
        );

    line_s <= degraded_s when degraded_sel_s = '1' else (tx_data_s xor invert_s);

    rx: nsl_line_coding.manchester.manchester_receiver_recovery
      generic map(
        clock_i_hz_c => clock_hz_c(i),
        signal_hz_c => signal_hz_c
        )
      port map(
        clock_i => clock_s(i),
        reset_n_i => reset_n_s(i),
        data_i => line_s,
        bit_o => rx_bit_s,
        valid_o => rx_valid_s,
        active_o => rx_active_s
        );

    -- Gathers bits of one burst, restarting on every carrier
    -- assertion.
    monitor: process(clock_s) is
      variable index_v : natural := 0;
      variable active_v : std_ulogic := '0';
      variable capture_v : std_ulogic_vector(0 to capture_max_c-1) := (others => '0');
    begin
      if rising_edge(clock_s(i)) then
        if rx_active_s = '1' and active_v = '0' then
          index_v := 0;
        end if;
        active_v := rx_active_s;

        if rx_valid_s = '1' then
          if index_v < capture_max_c then
            capture_v(index_v) := rx_bit_s;
          end if;
          index_v := index_v + 1;
        end if;

        rx_count_s <= index_v;
        rx_captured_s <= capture_v;
      end if;
    end process;

    stim: process is
      variable error_count_v : natural;
      variable lfsr_v : std_ulogic_vector(15 downto 0);

      procedure tx_send(bits : std_ulogic_vector) is
      begin
        for j in bits'range
        loop
          wait until falling_edge(clock_s(i));
          tx_bit_s <= bits(j);
          tx_valid_s <= '1';
          wait until rising_edge(clock_s(i)) and tx_ready_s = '1';
        end loop;

        wait until falling_edge(clock_s(i));
        tx_valid_s <= '0';
        tx_bit_s <= '0';
      end procedure;

      -- Drives the line directly, off the clock, with a static rate
      -- offset and a deterministic per-edge jitter.
      procedure degraded_send(bits : std_ulogic_vector) is
        variable edge_v, jitter_v : time;
      begin
        edge_v := now;

        for j in bits'range
        loop
          for h in 0 to 1
          loop
            if h = 0 then
              degraded_s <= not bits(j);
            else
              degraded_s <= bits(j);
            end if;

            lfsr_v := lfsr_v(14 downto 0)
                      & (lfsr_v(15) xor lfsr_v(13) xor lfsr_v(12) xor lfsr_v(10));
            jitter_v := (to_integer(unsigned(lfsr_v(3 downto 0))) - 8) * 1 ns;
            edge_v := edge_v + half_bit_skewed_c;
            wait for edge_v + jitter_v - now;
          end loop;
        end loop;

        degraded_s <= '0';
      end procedure;

      procedure check_quiet(scenario : string) is
      begin
        if rx_active_s /= '0' then
          log_error(name_c, scenario & ": carrier still asserted before burst");
          error_count_v := error_count_v + 1;
        end if;
      end procedure;

      procedure check_bits(scenario : string; expected : std_ulogic_vector) is
      begin
        if rx_count_s /= expected'length then
          log_error(name_c, scenario & ": recovered " & to_string(rx_count_s)
                    & " bits, expected " & to_string(expected'length));
          error_count_v := error_count_v + 1;
        elsif rx_captured_s(0 to expected'length-1) /= expected then
          log_error(name_c, scenario & ": recovered " & to_string(rx_captured_s(0 to expected'length-1))
                    & ", expected " & to_string(expected));
          error_count_v := error_count_v + 1;
        else
          log_info(name_c, scenario & ": " & to_string(expected'length) & " bits recovered");
        end if;

        if rx_active_s /= '0' then
          log_error(name_c, scenario & ": carrier still asserted after burst");
          error_count_v := error_count_v + 1;
        end if;
      end procedure;

    begin
      error_count_v := 0;
      lfsr_v := x"ace1";
      tx_valid_s <= '0';
      tx_bit_s <= '0';
      invert_s <= '0';
      degraded_sel_s <= '0';
      degraded_s <= '0';

      wait until reset_n_s(i) = '1';
      wait for 5 * bit_time_c;

      check_quiet("direct/a");
      tx_send(burst_a_c);
      wait for 5 * bit_time_c;
      check_bits("direct/a", burst_a_c);

      check_quiet("direct/b");
      tx_send(burst_b_c);
      wait for 5 * bit_time_c;
      check_bits("direct/b", burst_b_c);

      invert_s <= '1';
      wait for 5 * bit_time_c;

      check_quiet("inverted/a");
      tx_send(burst_a_c);
      wait for 5 * bit_time_c;
      check_bits("inverted/a", not burst_a_c);

      invert_s <= '0';
      degraded_sel_s <= '1';
      wait for 5 * bit_time_c;

      check_quiet("degraded/b");
      degraded_send(burst_b_c);
      wait for 5 * bit_time_c;
      check_bits("degraded/b", burst_b_c);

      if error_count_v = 0 then
        log_info(name_c, "all scenarios passed");
        fail_s(i) <= '0';
      else
        log_error(name_c, to_string(error_count_v) & " failure(s)");
        fail_s(i) <= '1';
      end if;

      done_s(i) <= '1';
      wait;
    end process;

  end generate;

  reporter: process is
    variable failed_v : boolean;
  begin
    failed_v := false;
    for i in 0 to config_count_c-1
    loop
      if done_s(i) /= '1' then
        wait until done_s(i) = '1';
      end if;

      if fail_s(i) = '1' then
        failed_v := true;
      end if;
    end loop;

    if failed_v then
      terminate(1);
    else
      terminate(0);
    end if;
  end process;

end;
