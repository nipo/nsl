library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_simulation, nsl_data;
use nsl_clocking.pll.all;
use nsl_data.text.all;

entity tb is
end entity;

architecture arch of tb is

  constant cfg_c : pll_config_t := pll_config(
    input_hz => 25_000_000,
    o0 => pll_output(100_000_000),
    o1 => pll_output(100_000_000, phase => (num => 1, den => 2)),
    o2 => pll_output(48_000_000),
    o3 => pll_output(22_579_200,
                     tolerance_ppm => 2000,
                     allow_fractional => true));

  constant measure_cycles_c : integer := 100;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic := '0';
  signal clocks_s : std_ulogic_vector(0 to cfg_c.output_count-1);
  signal locked_s : std_ulogic;
  signal done_s : boolean := false;

begin

  input_gen: process
  begin
    while not done_s loop
      clock_s <= '0';
      wait for 20 ns;
      clock_s <= '1';
      wait for 20 ns;
    end loop;
    wait;
  end process;

  reset_n_s <= '1' after 100 ns;

  dut: nsl_clocking.pll.pll_multi
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      clock_o => clocks_s,
      reset_n_i => reset_n_s,
      locked_o => locked_s
      );

  main: process
    constant mapping_c : pll_mapping_t := nsl_clocking.pll_backend.pll_solve(cfg_c);
    variable expected_hz, err : real;
    variable expected_period : time;
    variable t0 : time;

    -- rising_edge() requires a static signal name, this stands in
    -- for it on a computed index.
    procedure wait_rising(signal v: in std_ulogic_vector;
                          index: integer)
    is
      variable prev : std_ulogic;
    begin
      prev := v(index);
      loop
        wait on v;
        if prev = '0' and v(index) = '1' then
          return;
        end if;
        prev := v(index);
      end loop;
    end procedure;
  begin
    report to_string(cfg_c) & ": " & to_string(mapping_c)
      severity note;

    assert mapping_c.valid
      report "No mapping found"
      severity failure;
    assert mapping_c.refdiv = 1 and mapping_c.fbdiv = (num => 48, den => 1)
      and mapping_c.postdiv = 1 and mapping_c.vco_khz = 1_200_000
      report "Unexpected PLL core settings"
      severity failure;
    for i in 0 to 2 loop
      assert mapping_c.output(i).exact
        and mapping_c.output(i).hz = cfg_c.output(i).hz
        and mapping_c.output(i).port_index = i
        report "Unexpected settings for exact output " & to_string(i)
        severity failure;
    end loop;
    assert mapping_c.output(0).divisor = (num => 12, den => 1)
      and mapping_c.output(1).divisor = (num => 12, den => 1)
      and mapping_c.output(2).divisor = (num => 25, den => 1)
      report "Unexpected exact output divisors"
      severity failure;
    assert not mapping_c.output(3).exact
      report "Approximated output reported exact"
      severity failure;
    err := abs(mapping_output_hz(mapping_c, 3) - real(cfg_c.output(3).hz))
      / real(cfg_c.output(3).hz);
    assert err <= real(cfg_c.output(3).tolerance_ppm) * 1.0e-6
      report "Approximated output out of tolerance"
      severity failure;

    wait until locked_s = '1';

    -- Realized rates must match the rates predicted by the solver
    each_output: for i in 0 to cfg_c.output_count - 1 loop
      expected_hz := mapping_output_hz(mapping_c, i);
      expected_period := (1.0e9 / expected_hz) * 1 ns;
      wait_rising(clocks_s, i);
      t0 := now;
      cycles: for k in 1 to measure_cycles_c loop
        wait_rising(clocks_s, i);
      end loop;
      report "out" & to_string(i)
        & ": expected " & to_string(expected_hz / 1.0e6) & " MHz, "
        & "measured " & to_string(real(measure_cycles_c)
                                  / (real((now - t0) / 1 ps) * 1.0e-12)
                                  / 1.0e6) & " MHz"
        severity note;
      assert abs((now - t0) - measure_cycles_c * expected_period)
        <= measure_cycles_c * 1 fs
        report "Output " & to_string(i) & " rate off prediction"
        severity failure;
    end loop;

    -- Half-cycle phase relation between outputs 0 and 1
    wait until rising_edge(clocks_s(0));
    t0 := now;
    wait until rising_edge(clocks_s(1));
    assert abs((now - t0) - 5 ns) <= 1 fs
      report "Output 1 phase offset off request"
      severity failure;

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
