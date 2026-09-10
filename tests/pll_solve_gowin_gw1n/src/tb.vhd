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
    -- rPLL topology as built from hardware config, notably the
    -- sparse output divisor list folded into ranges

    t := nsl_clocking.pll_backend.pll_topology_get;
    assert t.output_count = 1
      report "Bad output count"
      severity failure;
    assert t.fbdiv.range_count = 1
      and t.fbdiv.ranges(0) = (min => 1, max => 64, step => 1)
      report "Bad fbdiv constraint"
      severity failure;
    assert t.pfd_khz_min = 3_000 and t.pfd_khz_max = 400_000
      and t.vco_khz_min = 400_000 and t.vco_khz_max = 1_200_000
      report "Bad frequency windows"
      severity failure;
    assert t.output(0).divisor.range_count = 3
      and t.output(0).divisor.ranges(0) = (min => 2, max => 4, step => 2)
      and t.output(0).divisor.ranges(1) = (min => 8, max => 16, step => 8)
      and t.output(0).divisor.ranges(2) = (min => 32, max => 128, step => 16)
      and t.output(0).divisor.frac_l2_den = 0
      report "Bad output divisor constraint"
      severity failure;

    -- Exact mapping

    cfg := pll_config(27_000_000, pll_output(108_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 32, den => 1)
      and m.vco_khz = 864_000
      and m.output(0).exact
      and m.output(0).divisor = (num => 8, den => 1)
      report "Unexpected mapping"
      severity failure;

    -- 48MHz is not exactly reachable from 27MHz on this block

    cfg := pll_config(27_000_000, pll_output(48_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Unreachable rate mapped"
      severity failure;

    -- Same rate with some slack

    cfg := pll_config(27_000_000,
                      pll_output(48_000_000, tolerance_ppm => 20_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No approximate mapping found"
      severity failure;
    assert m.refdiv = 2 and m.fbdiv = (num => 57, den => 1)
      and m.vco_khz = 769_500
      and not m.output(0).exact
      and m.output(0).divisor = (num => 16, den => 1)
      and m.output(0).hz = 48_093_750
      report "Unexpected approximate mapping"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
