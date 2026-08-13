library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

library nsl_logic;
use nsl_logic.gearbox.all;

library nsl_data;
use nsl_data.text.all;
use nsl_data.prbs.all;

-- Gearbox C2C testbench
--
-- Tests the constant-to-constant gearbox by:
-- 1. Input process: feeds preamble zeros, then PRBS data
-- 2. Output process: searches for marker, then verifies PRBS

entity tb is
  generic(
    input_width_c         : positive := 8;
    output_width_c        : positive := 16;
    input_clock_period_c  : time := 8 ns;
    output_clock_period_c : time := 16 ns
    );
end entity;

architecture arch of tb is

  signal clock_input_s : std_ulogic;
  signal clock_output_s : std_ulogic;
  signal faster_clock_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 1);

  signal in_s       : std_ulogic_vector(0 to input_width_c - 1);
  signal out_s      : std_ulogic_vector(0 to output_width_c - 1);
  signal ready_s    : std_ulogic;
  signal valid_s    : std_ulogic;  

  constant preamble_words_c : natural := 4;
  constant total_bits_c     : natural := 10000;

begin

  gen_input_slower: if input_clock_period_c > output_clock_period_c generate
  begin
    faster_clock_s <= clock_output_s;
  end generate;

  gen_output_slower: if input_clock_period_c < output_clock_period_c generate
  begin
    faster_clock_s <= clock_input_s;
  end generate;  

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count  => done_s'length
      )
    port map(
      clock_period(0) => output_clock_period_c,
      clock_period(1) => input_clock_period_c,
      reset_duration  => (others => 100 ns),
      clock_o(0)      => clock_output_s,
      clock_o(1)      => clock_input_s,      
      reset_n_o(0)    => reset_n_s,
      done_i          => done_s
      );

  dut: gearbox_c2c
    generic map(
      input_width_c      => input_width_c,
      output_width_c     => output_width_c,
      left_to_right_c        => true
      )
    port map(
      clock_i    => faster_clock_s,
      reset_n_i  => reset_n_s,
      in_i       => in_s,
      ready_o    => ready_s,
      out_o      => out_s,
      valid_o    => valid_s
      );

  -- Input generation process
  input_proc: process
    constant data_poly_c : prbs_state := prbs15;
    constant data_init_c : prbs_state(14 downto 0) := (others => '1');
    variable data_state  : prbs_state(14 downto 0);
    variable input_bits  : std_ulogic_vector(0 to input_width_c - 1);

    procedure put(data : std_ulogic_vector(0 to input_width_c - 1)) is
    begin
      in_s <= data;
      loop
        wait until rising_edge(clock_input_s);
        exit;
      end loop;
      wait for 1 ns;
    end procedure;

  begin
    done_s(0) <= '0';
    in_s <= (others => '0');
    data_state := data_init_c;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_input_s);
    wait for 1 ns;

    log_info("=== Input Process Started ===");

    -- Phase 1: Feed preamble (zeros)
    log_info("Feeding preamble (zeros)...");
    for i in 0 to preamble_words_c - 1 loop
      put((others => '0'));
    end loop;

    input_bits := (others => '0');
    input_bits(input_bits'right) := '1';
    put(input_bits);

    -- Phase 2: Feed PRBS data continuously
    log_info("Feeding PRBS data...");
    for word in 0 to (total_bits_c / input_width_c) + 9 loop
      input_bits := prbs_bit_string(data_state, data_poly_c, input_bits'length);
      data_state := prbs_forward(data_state, data_poly_c, input_bits'length);
      put(input_bits);
    end loop;

    log_info("Input process done");
    done_s(0) <= '1';
    wait;
  end process;

  -- Output verification process
  output_proc: process
    constant data_poly_c : prbs_state := prbs15;
    constant data_init_c : prbs_state(14 downto 0) := (others => '1');
    variable verify_state : prbs_state(14 downto 0);
    variable expected     : std_ulogic_vector(0 to output_width_c - 1);
    variable bits_verified : natural := 0;
    variable marker_pos   : integer := -1;
    variable partial_len  : integer;
    variable partial_exp  : std_ulogic_vector(0 to output_width_c - 1);
  begin
    done_s(1) <= '0';
    verify_state := data_init_c;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_output_s);
    wait for 1 ns;

    log_info("=== Output Process Started ===");

    -- Phase 1: Wait for valid output and find marker
    log_info("Searching for marker...");
    loop
      wait until rising_edge(clock_output_s);
      wait for 1 ns;

      -- Look for '1' in output
      marker_pos := -1;
      for i in 0 to output_width_c - 1 loop
        if out_s(i) = '1' then
          marker_pos := i;
          exit;
        end if;
      end loop;

      if marker_pos >= 0 then
        log_info("Marker found at position " & to_string(marker_pos));
        exit;
      end if;
    end loop;

    -- Phase 2: Verify PRBS
    log_info("Starting PRBS verification...");

    -- First partial word after marker (if any bits remain in this word)
    if marker_pos < output_width_c - 1 then
      partial_len := output_width_c - 1 - marker_pos;
      partial_exp(0 to partial_len - 1) := prbs_bit_string(verify_state, data_poly_c, partial_len);

      if out_s(marker_pos + 1 to output_width_c - 1) /= partial_exp(0 to partial_len - 1) then
        log_error("PRBS mismatch in first partial word: expected " &
                  to_string(partial_exp(0 to partial_len - 1)) &
                  ", got " & to_string(out_s(marker_pos + 1 to output_width_c - 1)));
        assert false report "PRBS mismatch" severity failure;
      end if;

      verify_state := prbs_forward(verify_state, data_poly_c, partial_len);
      bits_verified := bits_verified + partial_len;
    end if;

    -- Full words
    while bits_verified < total_bits_c loop
      wait until rising_edge(clock_output_s);
      wait for 1 ns;

      expected := prbs_bit_string(verify_state, data_poly_c, output_width_c);

      if out_s /= expected then
        log_error("PRBS mismatch at bit " & to_string(bits_verified) &
                  ": expected " & to_string(expected) &
                  ", got " & to_string(out_s));
        assert false report "PRBS mismatch" severity failure;
      end if;

      verify_state := prbs_forward(verify_state, data_poly_c, output_width_c);
      bits_verified := bits_verified + output_width_c;

      -- Progress report
      if bits_verified mod 1000 < output_width_c then
        log_info("Verified " & to_string(bits_verified) & " bits...");
      end if;
    end loop;

    log_info("=== TEST PASSED ===");
    log_info("Total bits verified: " & to_string(bits_verified));

    done_s(1) <= '1';
    wait;
  end process;

end architecture;
