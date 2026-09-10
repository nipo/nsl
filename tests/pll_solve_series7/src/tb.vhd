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

    -- Each block has its own VCO window, so the topology depends on
    -- which one the config names

    t := nsl_clocking.pll_backend.pll_topology_get(pll_c);
    assert t.vco_khz_min = 800_000 and t.vco_khz_max = 1_600_000
      report "Bad PLL VCO window"
      severity failure;
    assert t.output_count = 6
      and t.fbdiv.ranges(0) = (min => 1, max => 64, step => 1)
      and t.output(0).divisor.ranges(0) = (min => 1, max => 128, step => 1)
      report "Bad PLL topology"
      severity failure;

    t := nsl_clocking.pll_backend.pll_topology_get(mmcm_c);
    assert t.vco_khz_min = 600_000 and t.vco_khz_max = 1_200_000
      report "Bad MMCM VCO window"
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

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
