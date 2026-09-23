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
    -- Agilex 5 I/O PLL topology: N and M pre- and feedback counters,
    -- seven post-scale counters off the VCO, phase in eighths of a
    -- VCO period.

    t := nsl_clocking.pll_backend.pll_topology_get;
    assert t.output_count = 7
      report "Bad output count"
      severity failure;
    assert t.refdiv.ranges(0) = (min => 1, max => 110, step => 1)
      and t.fbdiv.ranges(0) = (min => 4, max => 320, step => 1)
      and t.postdiv.ranges(0) = (min => 1, max => 1, step => 1)
      report "Bad divider constraints"
      severity failure;
    assert t.pfd_khz_min = 10_000 and t.pfd_khz_max = 325_000
      and t.vco_khz_min = 600_000 and t.vco_khz_max = 3_200_000
      report "Bad frequency windows for the -4S grade of this part"
      severity failure;
    assert t.out_khz_max = 1_100_000
      report "Bad output ceiling for the -4S grade of this part"
      severity failure;
    assert t.output(6).divisor.ranges(0) = (min => 1, max => 510, step => 1)
      and t.output(6).divisor.frac_l2_den = 0
      and t.output(6).phase_vco_den = 8
      and t.output(6).phase_vco_step_max = 2047
      report "Bad output constraint"
      severity failure;

    -- What the DE25-Nano board asks for off its 50 MHz oscillator.
    -- The solver runs the VCO as fast as the window lets it.

    cfg := pll_config(50_000_000, pll_output(100_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 64, den => 1)
      and m.pfd_khz = 50_000 and m.vco_khz = 3_200_000
      and m.output(0).exact and m.output(0).port_index = 0
      and m.output(0).divisor = (num => 32, den => 1)
      report "Unexpected output settings"
      severity failure;

    -- Three outputs off one VCO rate

    cfg := pll_config(50_000_000,
                      pll_output(100_000_000),
                      pll_output(125_000_000),
                      pll_output(200_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      and m.output(0).exact and m.output(1).exact and m.output(2).exact
      report "No multi-output mapping found"
      severity failure;

    -- A reference below the PFD floor is unusable: N only divides it
    -- further down.

    cfg := pll_config(8_000_000, pll_output(80_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Reference below the PFD floor accepted"
      severity failure;

    -- The floor itself is reachable, and M at 320 lands on the top of
    -- the VCO window.

    cfg := pll_config(10_000_000, pll_output(3_200_000_000 / 4));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "Reference at the PFD floor rejected"
      severity failure;
    assert m.refdiv = 1 and m.pfd_khz = 10_000
      and m.fbdiv = (num => 320, den => 1) and m.vco_khz = 3_200_000
      and m.output(0).divisor = (num => 4, den => 1)
      report "Unexpected settings at the top of the VCO window"
      severity failure;

    -- A rate so low that no post-scale counter divides the VCO down
    -- to it: 600 MHz over 510 is 1.18 MHz.

    cfg := pll_config(50_000_000, pll_output(1_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Rate below the post-scale counters mapped"
      severity failure;

    -- The bottom of the window: 600 MHz over 500.

    cfg := pll_config(50_000_000, pll_output(1_200_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid and m.vco_khz = 600_000
      and m.output(0).divisor = (num => 500, den => 1)
      report "Rate at the bottom of the VCO window rejected"
      severity failure;

    -- The output ceiling: 1.2 GHz is inside the VCO window and still
    -- refused on a -4S part, 1.1 GHz is not.

    cfg := pll_config(50_000_000, pll_output(1_200_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Rate above the output ceiling mapped"
      severity failure;

    cfg := pll_config(50_000_000, pll_output(1_100_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "Rate at the output ceiling rejected"
      severity failure;

    -- A quarter-cycle phase is a whole number of VCO eighths whatever
    -- the divisor.

    cfg := pll_config(50_000_000,
                      pll_output(100_000_000),
                      pll_output(100_000_000, phase => (num => 1, den => 4)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid and m.output(1).phase = (num => 1, den => 4)
      report "Quarter-cycle phase not mapped"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
