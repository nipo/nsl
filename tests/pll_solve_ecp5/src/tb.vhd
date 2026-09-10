library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_simulation;
use nsl_clocking.pll.all;

entity tb is
end entity;

architecture arch of tb is
begin

  main: process
    variable t : pll_topology_t;
    variable cfg : pll_config_t;
    variable m : pll_mapping_t;
  begin
    -- EHXPLLL topology: CLKOP reserved for feedback, three user
    -- outputs

    t := nsl_clocking.pll_backend.pll_topology_get;
    assert t.output_count = 3
      report "Bad output count"
      severity failure;
    assert t.refdiv.ranges(0) = (min => 1, max => 128, step => 1)
      and t.fbdiv.ranges(0) = (min => 1, max => 128, step => 1)
      report "Bad divider constraints"
      severity failure;
    assert t.pfd_khz_min = 8_000 and t.pfd_khz_max = 400_000
      and t.vco_khz_min = 400_000 and t.vco_khz_max = 800_000
      report "Bad frequency windows"
      severity failure;
    assert t.output(1).divisor.ranges(0) = (min => 1, max => 128, step => 1)
      and t.output(1).divisor.frac_l2_den = 0
      report "Bad output divisor constraint"
      severity failure;

    -- Multi-output exact mapping

    cfg := pll_config(25_000_000,
                      pll_output(100_000_000),
                      pll_output(200_000_000),
                      pll_output(50_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 32, den => 1)
      and m.vco_khz = 800_000
      report "Unexpected core settings"
      severity failure;
    assert m.output(0).exact and m.output(0).port_index = 0
      and m.output(0).divisor = (num => 8, den => 1)
      and m.output(1).exact and m.output(1).port_index = 1
      and m.output(1).divisor = (num => 4, den => 1)
      and m.output(2).exact and m.output(2).port_index = 2
      and m.output(2).divisor = (num => 16, den => 1)
      report "Unexpected output settings"
      severity failure;

    -- 133MHz needs a multiplier beyond the feedback range

    cfg := pll_config(25_000_000, pll_output(133_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Unreachable rate mapped"
      severity failure;

    -- Audio master rate with slack, integer divisors only

    cfg := pll_config(25_000_000,
                      pll_output(22_579_200, tolerance_ppm => 25_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No approximate mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 28, den => 1)
      and m.vco_khz = 700_000
      and not m.output(0).exact
      and m.output(0).divisor = (num => 31, den => 1)
      and m.output(0).hz = 22_580_645
      report "Unexpected approximate mapping"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
