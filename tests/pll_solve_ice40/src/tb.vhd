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
    -- Named choices: the reference pin type picks the primitive,
    -- the routing picks the port an output leaves on.  Defaults are
    -- what pll_basic used to imply.

    assert nsl_clocking.pll_backend.pll_reference_id("DEFAULT")
      = nsl_clocking.pll_backend.pll_reference_id("PAD")
      report "PAD is not the default reference input"
      severity failure;
    assert nsl_clocking.pll_backend.pll_reference_id("CORE")
      /= nsl_clocking.pll_backend.pll_reference_id("PAD")
      report "Reference inputs are not told apart"
      severity failure;
    assert nsl_clocking.pll_backend.pll_routing_id("DEFAULT")
      = nsl_clocking.pll_backend.pll_routing_id("GLOBAL")
      report "GLOBAL is not the default routing"
      severity failure;
    assert nsl_clocking.pll_backend.pll_routing_id("CORE")
      /= nsl_clocking.pll_backend.pll_routing_id("GLOBAL")
      report "Output routings are not told apart"
      severity failure;

    -- A named choice travels in the config, untouched
    cfg := pll_config(12_000_000,
                      pll_output(48_000_000,
                                 routing => nsl_clocking.pll_backend.pll_routing_id("CORE")),
                      reference_input => nsl_clocking.pll_backend.pll_reference_id("CORE"));
    assert cfg.reference_input = nsl_clocking.pll_backend.pll_reference_id("CORE")
      and cfg.output(0).routing = nsl_clocking.pll_backend.pll_routing_id("CORE")
      report "Named choices did not reach the config"
      severity failure;

    -- and does not disturb the mapping
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    assert m.valid and m.output(0).exact
      and m.output(0).divisor = (num => 16, den => 1)
      report "Named choices changed the mapping"
      severity failure;

    -- SB_PLL40 topology, notably the power-of-two output divisor

    t := nsl_clocking.pll_backend.pll_topology_get;
    assert t.output_count = 1
      report "Bad output count"
      severity failure;
    assert t.refdiv.ranges(0) = (min => 1, max => 16, step => 1)
      and t.fbdiv.ranges(0) = (min => 1, max => 128, step => 1)
      report "Bad divider constraints"
      severity failure;

    -- The icestick demo rate, needing the upper DIVF half
    cfg := pll_config(12_000_000, pll_output(60_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid and m.output(0).exact
      and m.fbdiv = (num => 80, den => 1)
      and m.vco_khz = 960_000
      and m.output(0).divisor = (num => 16, den => 1)
      report "Unexpected upper-DIVF mapping"
      severity failure;
    assert t.pfd_khz_min = 10_000 and t.pfd_khz_max = 133_000
      and t.vco_khz_min = 533_000 and t.vco_khz_max = 1_066_000
      report "Bad frequency windows"
      severity failure;
    assert t.output(0).divisor.range_count = 6
      and t.output(0).divisor.ranges(0) = (min => 2, max => 2, step => 1)
      and t.output(0).divisor.ranges(5) = (min => 64, max => 64, step => 1)
      report "Bad output divisor constraint"
      severity failure;

    -- Exact mapping

    cfg := pll_config(12_000_000, pll_output(48_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 64, den => 1)
      and m.vco_khz = 768_000
      and m.output(0).exact
      and m.output(0).divisor = (num => 16, den => 1)
      report "Unexpected mapping"
      severity failure;

    -- 20MHz is not exactly reachable from 12MHz on a power-of-two
    -- output divisor

    cfg := pll_config(12_000_000, pll_output(20_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Unreachable rate mapped"
      severity failure;

    -- Same rate with some slack

    cfg := pll_config(12_000_000,
                      pll_output(20_000_000, tolerance_ppm => 20_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No approximate mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 53, den => 1)
      and m.vco_khz = 636_000
      and not m.output(0).exact
      and m.output(0).divisor = (num => 32, den => 1)
      and m.output(0).hz = 19_875_000
      report "Unexpected approximate mapping"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
