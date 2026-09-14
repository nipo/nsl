library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_simulation;
use nsl_clocking.pll.all;

entity tb is
end entity;

architecture arch of tb is

  constant pll_c : natural := nsl_clocking.pll_backend.pll_implementation_id("PLL");
  constant mmcm_c : natural := nsl_clocking.pll_backend.pll_implementation_id("MMCM");

begin

  main: process
    variable t : pll_topology_t;
    variable cfg : pll_config_t;
    variable m : pll_mapping_t;
  begin
    -- Both blocks of a Series-7 part are named, and they are not the
    -- same block

    assert pll_c /= mmcm_c
      report "Clock managers are not told apart"
      severity failure;
    assert nsl_clocking.pll_backend.pll_implementation_id("DEFAULT") = 0
      report "Default implementation is not the default id"
      severity failure;

    -- Each block has its own VCO window, its own input divider and
    -- its own phase detector window, so the topology depends on which
    -- one the config names

    t := nsl_clocking.pll_backend.pll_topology_get(pll_c);
    assert t.vco_khz_min = 800_000 and t.vco_khz_max = 1_600_000
      report "Bad PLL VCO window"
      severity failure;
    assert t.output_count = 6
      and t.fbdiv.ranges(0) = (min => 2, max => 64, step => 1)
      and t.refdiv.ranges(0) = (min => 1, max => 56, step => 1)
      and t.output(0).divisor.ranges(0) = (min => 1, max => 128, step => 1)
      report "Bad PLL topology"
      severity failure;
    assert t.pfd_khz_min = 19_000
      report "PLL phase detector floor is not stated"
      severity failure;

    t := nsl_clocking.pll_backend.pll_topology_get(mmcm_c);
    assert t.vco_khz_min = 600_000 and t.vco_khz_max = 1_200_000
      report "Bad MMCM VCO window"
      severity failure;
    assert t.output_count = 7
      and t.refdiv.ranges(0) = (min => 1, max => 106, step => 1)
      and t.pfd_khz_min = 10_000
      report "Bad MMCM topology"
      severity failure;

    -- Both blocks delay an output by whole and eighth VCO cycles, and
    -- run out of shifter at 511 eighths

    assert t.output(0).phase_vco_den = 8
      and t.output(0).phase_vco_step_max = 511
      and t.output(6).phase_vco_den = 8
      report "MMCM outputs state no VCO-relative phase grid"
      severity failure;

    -- Same request, two blocks, two mappings

    cfg := pll_config(100_000_000,
                      pll_output(200_000_000),
                      pll_output(50_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the default block: " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping on the default block"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 16, den => 1)
      and m.vco_khz = 1_600_000
      and m.output(0).exact and m.output(0).divisor = (num => 8, den => 1)
      and m.output(1).exact and m.output(1).divisor = (num => 32, den => 1)
      report "Unexpected mapping on the default block"
      severity failure;

    cfg := pll_config(100_000_000,
                      pll_output(200_000_000),
                      pll_output(50_000_000),
                      implementation => mmcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the MMCM: " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping on the MMCM"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 12, den => 1)
      and m.vco_khz = 1_200_000
      and m.output(0).exact and m.output(0).divisor = (num => 6, den => 1)
      and m.output(1).exact and m.output(1).divisor = (num => 24, den => 1)
      report "Unexpected mapping on the MMCM"
      severity failure;

    -- The output divider tops out at 128, so nothing below a
    -- hundred-and-twenty-eighth of the lowest VCO rate is reachable

    cfg := pll_config(100_000_000, pll_output(5_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Unreachable rate mapped"
      severity failure;

    -- The phase detector window is stated, and the two blocks do not
    -- state the same one: a 10MHz reference is below what a PLL
    -- compares and right at what an MMCM does

    cfg := pll_config(10_000_000, pll_output(100_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the PLL: " & to_string(m)
      severity note;
    assert not m.valid
      report "PLL compared a reference below its phase detector floor"
      severity failure;

    cfg := pll_config(10_000_000, pll_output(100_000_000),
                      implementation => mmcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the MMCM: " & to_string(m)
      severity note;
    assert m.valid and m.refdiv = 1 and m.pfd_khz = 10_000
      report "MMCM refused a reference at its phase detector floor"
      severity failure;

    -- Rates the feedback factor alone cannot reach come through the
    -- input divider: 12MHz out of 125MHz needs a VCO that is a
    -- multiple of 300MHz, and 125 times anything is not

    cfg := pll_config(125_000_000,
                      pll_output(12_000_000),
                      pll_output(100_000_000),
                      implementation => mmcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping through the input divider"
      severity failure;
    assert m.refdiv = 5 and m.fbdiv = (num => 48, den => 1)
      and m.pfd_khz = 25_000 and m.vco_khz = 1_200_000
      and m.output(0).divisor = (num => 100, den => 1)
      report "Unexpected mapping through the input divider"
      severity failure;

    -- The same request with quarter-cycle phases walks the VCO down.
    -- Three quarters of a divide-by-100 output is 600 eighths of a
    -- VCO cycle, past what the shifter holds; a divide-by-75 output
    -- needs 450 and fits.

    cfg := pll_config(125_000_000,
                      pll_output(12_000_000),
                      pll_output(12_000_000, phase => (num => 1, den => 4)),
                      pll_output(12_000_000, phase => (num => 1, den => 2)),
                      pll_output(12_000_000, phase => (num => 3, den => 4)),
                      pll_output(100_000_000),
                      implementation => mmcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping with phase shifts"
      severity failure;
    assert m.refdiv = 5 and m.fbdiv = (num => 36, den => 1)
      and m.vco_khz = 900_000
      and m.output(0).divisor = (num => 75, den => 1)
      and m.output(3).divisor = (num => 75, den => 1)
      report "Phase shifts did not walk the VCO down"
      severity failure;
    assert m.output(1).phase = (num => 1, den => 4)
      and m.output(3).phase = (num => 3, den => 4)
      report "Phase did not reach the mapping"
      severity failure;

    -- The grid moves with the divisor, so a phase off one divisor's
    -- grid may sit on another's: a third of a cycle needs a divisor
    -- that is a multiple of three, and 200MHz has one, VCO 1200 over
    -- six.

    cfg := pll_config(100_000_000,
                      pll_output(200_000_000, phase => (num => 1, den => 3)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid and m.output(0).divisor = (num => 6, den => 1)
      report "Solver did not move to a divisor carrying the phase"
      severity failure;

    -- A ninth needs a divisor that is a multiple of nine, and every
    -- divisor reaching 200MHz from the PLL window is between four and
    -- eight.

    cfg := pll_config(100_000_000,
                      pll_output(200_000_000, phase => (num => 1, den => 9)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Off-grid phase accepted"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
