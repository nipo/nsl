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
    -- PLLA topology as built from hardware config

    t := nsl_clocking.pll_backend.pll_topology_get;
    assert t.output_count = 7
      report "Bad output count"
      severity failure;
    assert t.refdiv.range_count = 1
      and t.refdiv.ranges(0) = (min => 1, max => 64, step => 1)
      report "Bad refdiv constraint"
      severity failure;
    assert t.fbdiv.range_count = 1
      and t.fbdiv.ranges(0) = (min => 2, max => 128, step => 1)
      and t.fbdiv.frac_l2_den = 0
      report "Bad fbdiv constraint"
      severity failure;
    assert t.pfd_khz_min = 19_000 and t.pfd_khz_max = 81_250
      and t.vco_khz_min = 700_000 and t.vco_khz_max = 1_400_000
      report "Bad frequency windows"
      severity failure;
    assert t.output(0).divisor.range_count = 1
      and t.output(0).divisor.ranges(0) = (min => 1, max => 128, step => 1)
      and t.output(0).divisor.frac_l2_den = 3
      and t.output(1).divisor.frac_l2_den = 0
      report "Bad output divisor constraints"
      severity failure;

    -- Exact integer mapping

    cfg := pll_config(50_000_000,
                      pll_output(200_000_000),
                      pll_output(125_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 20, den => 1)
      and m.vco_khz = 1_000_000
      report "Unexpected core settings"
      severity failure;
    assert m.output(0).exact and m.output(0).port_index = 0
      and m.output(0).divisor = (num => 5, den => 1)
      and m.output(1).exact and m.output(1).port_index = 1
      and m.output(1).divisor = (num => 8, den => 1)
      report "Unexpected output settings"
      severity failure;

    -- Exact mapping needing the fractional divisor of port 0

    cfg := pll_config(50_000_000,
                      pll_output(160_000_000, allow_fractional => true),
                      pll_output(150_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No fractional mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 24, den => 1)
      and m.vco_khz = 1_200_000
      report "Unexpected fractional core settings"
      severity failure;
    assert m.output(0).exact and m.output(0).port_index = 0
      and m.output(0).divisor = (num => 60, den => 8)
      and m.output(1).exact and m.output(1).port_index = 1
      and m.output(1).divisor = (num => 8, den => 1)
      report "Unexpected fractional output settings"
      severity failure;

    -- Phase shift: PLLA moves an output by whole and eighth VCO
    -- cycles, so what a config can ask for depends on the divisor
    -- the solver lands on.  A quarter cycle of a divide-by-7 output
    -- is 14 eighths of a VCO cycle, which is on the grid.

    assert t.output(0).phase_vco_den = 8 and t.output(6).phase_vco_den = 8
      report "PLLA outputs state no VCO-relative phase grid"
      severity failure;

    cfg := pll_config(50_000_000,
                      pll_output(200_000_000),
                      pll_output(200_000_000, phase => (num => 1, den => 4)),
                      pll_output(200_000_000, phase => (num => 1, den => 2)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping with phase shifts"
      severity failure;
    assert m.vco_khz = 1_400_000
      and m.output(0).divisor = (num => 7, den => 1)
      and m.output(1).divisor = (num => 7, den => 1)
      and m.output(2).divisor = (num => 7, den => 1)
      report "Phase shifts disturbed the divisors"
      severity failure;
    assert m.output(1).phase = (num => 1, den => 4)
      and m.output(2).phase = (num => 1, den => 2)
      report "Phase did not reach the mapping"
      severity failure;

    -- The grid moves with the divisor, so a phase off one divisor's
    -- grid may sit on another's: a fifth of a cycle needs a divisor
    -- that is a multiple of five, and 200MHz has one, VCO 1000 over
    -- five.
    cfg := pll_config(50_000_000,
                      pll_output(200_000_000, phase => (num => 1, den => 8)));
    assert nsl_clocking.pll_backend.pll_solve(cfg).valid
      report "On-grid phase refused"
      severity failure;

    cfg := pll_config(50_000_000,
                      pll_output(200_000_000, phase => (num => 1, den => 5)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    assert m.valid and m.output(0).divisor = (num => 5, den => 1)
      report "Solver did not move to a divisor carrying the phase"
      severity failure;

    -- A ninth needs a divisor that is a multiple of nine, and no
    -- divisor reaching 200MHz from this VCO window is one.
    cfg := pll_config(50_000_000,
                      pll_output(200_000_000, phase => (num => 1, den => 9)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Off-grid phase accepted"
      severity failure;

    -- 74.25MHz is not reachable from 50MHz, even on eighths

    cfg := pll_config(50_000_000,
                      pll_output(74_250_000, allow_fractional => true));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Unreachable rate mapped"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
