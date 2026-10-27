library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_simulation, nsl_data, work;
use nsl_simulation.logging.all;
use nsl_data.text.all;
use work.bench.all;

-- Models a delay line of tap_count_c taps and a serdes of
-- slip_count_c positions, and checks the aligner settles on the
-- expected tap for each scenario.
entity aligner_bench is
  generic(
    tap_count_c: integer;
    scenarios_c: scenario_vector
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    done_o: out std_ulogic
    );
end entity;

architecture beh of aligner_bench is

  signal tap_s: integer range 0 to tap_count_c-1;
  signal slip_s: integer range 0 to slip_count_c-1;
  signal eye_s: std_ulogic_vector(0 to tap_count_max_c-1);
  signal eye_slip_s: integer range 0 to slip_count_c-1;
  signal delay_shift_s, delay_mark_s, serdes_shift_s, serdes_mark_s,
    valid_s, ready_s, aligner_reset_n_s: std_ulogic;

begin

  model: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if delay_shift_s = '1' then
        tap_s <= (tap_s + 1) mod tap_count_c;
      end if;
      if serdes_shift_s = '1' then
        slip_s <= (slip_s + 1) mod slip_count_c;
      end if;
    end if;

    -- Line and serdes are not at their marks when the aligner starts.
    if reset_n_i = '0' then
      tap_s <= tap_count_c / 3;
      slip_s <= 7;
    end if;
  end process;

  delay_mark_s <= '1' when tap_s = 0 else '0';
  serdes_mark_s <= '1' when slip_s = 0 else '0';
  valid_s <= '1' when slip_s = eye_slip_s and eye_s(tap_s) = '1' else '0';

  dut: nsl_io.delay.input_delay_aligner
    port map(
      clock_i => clock_i,
      reset_n_i => aligner_reset_n_s,

      delay_shift_o => delay_shift_s,
      delay_mark_i => delay_mark_s,
      serdes_shift_o => serdes_shift_s,
      serdes_mark_i => serdes_mark_s,

      valid_i => valid_s,
      ready_o => ready_s
      );

  stim: process is
    variable s: scenario_t;
  begin
    done_o <= '0';
    aligner_reset_n_s <= '0';
    wait until reset_n_i = '1';

    for i in scenarios_c'range
    loop
      s := scenarios_c(i);
      wait until falling_edge(clock_i);
      eye_s <= s.eye;
      eye_slip_s <= s.slip;
      aligner_reset_n_s <= '0';
      wait until falling_edge(clock_i);
      aligner_reset_n_s <= '1';

      wait until ready_s = '1' for 2 ms;
      assert ready_s = '1'
        report "Taps " & to_string(tap_count_c) & ", scenario " & to_string(i)
        & ": no lock"
        severity failure;

      -- Lock must be stable.
      for c in 0 to 99
      loop
        wait until falling_edge(clock_i);
        assert ready_s = '1' and delay_shift_s = '0' and serdes_shift_s = '0'
          report "Taps " & to_string(tap_count_c) & ", scenario " & to_string(i)
          & ": lock lost"
          severity failure;
      end loop;

      assert slip_s = s.slip
        report "Taps " & to_string(tap_count_c) & ", scenario " & to_string(i)
        & ": slip " & to_string(slip_s) & ", expected " & to_string(s.slip)
        severity failure;
      assert s.tap = any_c or tap_s = s.tap
        report "Taps " & to_string(tap_count_c) & ", scenario " & to_string(i)
        & ": tap " & to_string(tap_s) & ", expected " & to_string(s.tap)
        severity failure;

      log_info("Taps " & to_string(tap_count_c) & ", scenario " & to_string(i)
               & ": locked on slip " & to_string(slip_s)
               & ", tap " & to_string(tap_s));
    end loop;

    done_o <= '1';
    wait;
  end process;

end architecture;
