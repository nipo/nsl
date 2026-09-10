library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_simulation;
use nsl_clocking.pll.all;

entity tb is
end entity;

architecture arch of tb is

  constant pll_c : natural := nsl_clocking.pll_backend.pll_implementation_id("PLL");
  constant dcm_c : natural := nsl_clocking.pll_backend.pll_implementation_id("DCM");

begin

  main: process
    variable t : pll_topology_t;
    variable cfg : pll_config_t;
    variable m : pll_mapping_t;
  begin
    -- A Spartan-6 carries a PLL and a DCM, and they are not the same
    -- block

    assert pll_c /= dcm_c
      report "Clock managers are not told apart"
      severity failure;

    t := nsl_clocking.pll_backend.pll_topology_get(pll_c);
    assert t.output_count = 6
      and t.vco_khz_min = 400_000 and t.vco_khz_max = 1_000_000
      report "Bad PLL topology"
      severity failure;

    -- The DCM has no VCO: its multiplier feeds the output divider
    -- directly, so the window is the synthesizer's output window and
    -- there is one output
    t := nsl_clocking.pll_backend.pll_topology_get(dcm_c);
    assert t.output_count = 1
      and t.vco_khz_min = 500 and t.vco_khz_max = 200_000
      and t.fbdiv.ranges(0) = (min => 1, max => 32, step => 1)
      and t.output(0).divisor.ranges(0) = (min => 1, max => 32, step => 1)
      report "Bad DCM topology"
      severity failure;

    -- Exact mapping on the PLL

    cfg := pll_config(50_000_000,
                      pll_output(125_000_000),
                      pll_output(25_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the PLL: " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping on the PLL"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 20, den => 1)
      and m.vco_khz = 1_000_000
      and m.output(0).exact and m.output(0).divisor = (num => 8, den => 1)
      and m.output(1).exact and m.output(1).divisor = (num => 40, den => 1)
      report "Unexpected mapping on the PLL"
      severity failure;

    -- Exact mapping on the DCM

    cfg := pll_config(50_000_000,
                      pll_output(25_000_000),
                      implementation => dcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the DCM: " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping on the DCM"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 4, den => 1)
      and m.vco_khz = 200_000
      and m.output(0).exact and m.output(0).divisor = (num => 8, den => 1)
      report "Unexpected mapping on the DCM"
      severity failure;

    -- The DCM's factors are far shorter than the PLL's: a rate the
    -- PLL reaches is out of the DCM's reach

    cfg := pll_config(50_000_000, pll_output(125_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    assert m.valid
      report "PLL cannot reach 125MHz"
      severity failure;

    cfg := pll_config(50_000_000,
                      pll_output(125_000_000),
                      implementation => dcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & " on the DCM: " & to_string(m)
      severity note;
    assert not m.valid
      report "DCM reached a rate its factors forbid"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
