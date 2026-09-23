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
    -- Cyclone 10 LP topology: N and M pre- and feedback counters,
    -- five post-scale counters, and a VCO window widened downwards
    -- by the post-scale counter K.

    t := nsl_clocking.pll_backend.pll_topology_get;
    assert t.output_count = 5
      report "Bad output count"
      severity failure;
    assert t.refdiv.ranges(0) = (min => 1, max => 512, step => 1)
      and t.fbdiv.ranges(0) = (min => 1, max => 512, step => 1)
      and t.postdiv.ranges(0) = (min => 1, max => 1, step => 1)
      report "Bad divider constraints"
      severity failure;
    assert t.pfd_khz_min = 5_000 and t.pfd_khz_max = 325_000
      and t.vco_khz_min = 300_000 and t.vco_khz_max = 1_300_000
      report "Bad frequency windows"
      severity failure;
    assert t.output(4).divisor.ranges(0) = (min => 1, max => 512, step => 1)
      and t.output(4).divisor.frac_l2_den = 0
      report "Bad output divisor constraint"
      severity failure;

    -- What the TEI0003 board asks for: its 12 MHz oscillator clears
    -- the 5 MHz PFD floor with N = 1, leaving the whole VCO window
    -- reachable in 12 MHz steps.

    cfg := pll_config(12_000_000, pll_output(80_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 100, den => 1)
      and m.postdiv = 1
      and m.pfd_khz = 12_000 and m.vco_khz = 1_200_000
      report "Unexpected core settings"
      severity failure;
    assert m.output(0).exact and m.output(0).port_index = 0
      and m.output(0).divisor = (num => 15, den => 1)
      report "Unexpected output settings"
      severity failure;

    -- Three outputs off one VCO rate

    cfg := pll_config(12_000_000,
                      pll_output(80_000_000),
                      pll_output(40_000_000),
                      pll_output(100_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No multi-output mapping found"
      severity failure;
    assert m.vco_khz = 1_200_000 and m.postdiv = 1
      and m.output(0).divisor = (num => 15, den => 1)
      and m.output(1).divisor = (num => 30, den => 1)
      and m.output(2).divisor = (num => 12, den => 1)
      and m.output(0).exact and m.output(1).exact and m.output(2).exact
      report "Unexpected multi-output settings"
      severity failure;

    -- A reference below the PFD floor is unusable whatever the rate
    -- asked for: N only divides it further down.

    cfg := pll_config(4_000_000, pll_output(80_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Reference below the PFD floor accepted"
      severity failure;

    -- The floor itself is reachable, and this one lands on the top
    -- of the VCO window

    cfg := pll_config(5_000_000, pll_output(100_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "Reference at the PFD floor rejected"
      severity failure;
    assert m.refdiv = 1 and m.pfd_khz = 5_000
      and m.fbdiv = (num => 260, den => 1) and m.vco_khz = 1_300_000
      and m.output(0).divisor = (num => 13, den => 1)
      and m.output(0).exact
      report "Unexpected settings at the window edges"
      severity failure;

    -- One VCO step above the ceiling, with C at one, is out of
    -- reach

    cfg := pll_config(12_000_000, pll_output(1_308_000_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Rate above the VCO ceiling mapped"
      severity failure;

    -- A rate so low that no post-scale counter divides the VCO down
    -- to it

    cfg := pll_config(12_000_000, pll_output(10_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Rate below the post-scale counters mapped"
      severity failure;

    -- The bottom of the VCO window is only reachable with K at two,
    -- and this rate needs it: a post-scale counter reaching 512
    -- leaves 586 kHz as the lowest rate a 300 MHz VCO carries.

    cfg := pll_config(12_000_000, pll_output(600_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "Rate at the bottom of the VCO window rejected"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 25, den => 1)
      and m.vco_khz = 300_000
      and m.output(0).divisor = (num => 500, den => 1)
      and m.output(0).exact
      report "Unexpected settings at the bottom of the VCO window"
      severity failure;

    -- ALTPLL rounds a phase shift to the eighth of a VCO period
    -- nearest to it, and the VCO rate is the vendor's to pick, so
    -- the block offers no phase this abstraction can promise.

    cfg := pll_config(12_000_000,
                      pll_output(80_000_000),
                      pll_output(80_000_000, phase => (num => 1, den => 4)));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert not m.valid
      report "Phase shift mapped"
      severity failure;

    -- Audio master rate, which no integer counter chain reaches
    -- exactly from 12 MHz

    cfg := pll_config(12_000_000, pll_output(22_579_200));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    assert not m.valid
      report "Audio rate mapped exactly"
      severity failure;

    cfg := pll_config(12_000_000,
                      pll_output(22_579_200, tolerance_ppm => 25_000));
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid and not m.output(0).exact
      report "No approximate mapping found"
      severity failure;
    assert m.refdiv = 2 and m.fbdiv = (num => 143, den => 1)
      and m.postdiv = 1 and m.vco_khz = 858_000
      and m.output(0).divisor = (num => 38, den => 1)
      and m.output(0).hz = 22_578_947
      report "Unexpected approximate mapping"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
