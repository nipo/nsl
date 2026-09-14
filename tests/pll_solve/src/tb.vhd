library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_simulation;
use nsl_clocking.pll.all;

entity tb is
end entity;

architecture arch of tb is

  constant od_int_c : pll_divisor_constraint_t := pll_divisor(pll_range(1, 128));
  constant od_frac_c : pll_divisor_constraint_t := pll_divisor(pll_range(1, 128),
                                                              frac_l2_den => 3);
  constant no_out_c : pll_output_topology_t := (divisor => pll_divisor_unity_c,
                                                phase_den => 0, phase_step_max => 0,
                                                phase_vco_den => 0, phase_vco_step_max => 0);

  -- Flexible block, fractional divisor on port 0 only
  constant topo_a_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 64)),
    fbdiv => pll_divisor(pll_range(1, 64)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 1_000,
    pfd_khz_max => 50_000,
    vco_khz_min => 400_000,
    vco_khz_max => 1_200_000,
    output_count => 4,
    output => (0 => (divisor => od_frac_c,
                     phase_den => 0, phase_step_max => 0,
                     phase_vco_den => 0, phase_vco_step_max => 0),
               1 | 2 | 3 => (divisor => od_int_c,
                            phase_den => 0, phase_step_max => 0,
                            phase_vco_den => 0, phase_vco_step_max => 0),
               others => no_out_c));

  -- Locked reference divisor and output divisor, only feedback and
  -- the fractional part of the output divisor are free
  constant topo_b_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 1)),
    fbdiv => pll_divisor(pll_range(17, 50)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 1_000,
    pfd_khz_max => 100_000,
    vco_khz_min => 400_000,
    vco_khz_max => 1_200_000,
    output_count => 1,
    output => (0 => (divisor => pll_divisor(pll_range(16, 16),
                                            frac_l2_den => 3),
                     phase_den => 0, phase_step_max => 0,
                     phase_vco_den => 0, phase_vco_step_max => 0),
               others => no_out_c));

  -- Two ports with disjoint divisor ranges, forcing assignment to
  -- cross the request order
  constant topo_c_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 64)),
    fbdiv => pll_divisor(pll_range(1, 64)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 1_000,
    pfd_khz_max => 50_000,
    vco_khz_min => 400_000,
    vco_khz_max => 1_200_000,
    output_count => 2,
    output => (0 => (divisor => pll_divisor(pll_range(1, 10)),
                     phase_den => 0, phase_step_max => 0,
                     phase_vco_den => 0, phase_vco_step_max => 0),
               1 => (divisor => pll_divisor(pll_range(11, 128)),
                     phase_den => 0, phase_step_max => 0,
                     phase_vco_den => 0, phase_vco_step_max => 0),
               others => no_out_c));

begin

  main: process
    variable cfg : pll_config_t;
    variable m, m2 : pll_mapping_t;
    variable dc : pll_divisor_constraint_t;
  begin
    -- Constructor and constraint checks

    cfg := pll_config(12_000_000,
                      pll_output(1_000_000),
                      pll_output(2_000_000));
    assert cfg.output_count = 2
      report "Bad output count"
      severity failure;
    assert cfg.output(1).hz = 2_000_000
      report "Bad output rate"
      severity failure;

    dc := pll_divisor(pll_range(2, 128, 2), pll_range(3, 3));
    assert is_allowed(dc, (num => 4, den => 1))
      report "Even value refused"
      severity failure;
    assert is_allowed(dc, (num => 3, den => 1))
      report "Extra value refused"
      severity failure;
    assert not is_allowed(dc, (num => 5, den => 1))
      report "Odd value accepted"
      severity failure;
    assert not is_allowed(dc, (num => 129, den => 1))
      report "Out of range value accepted"
      severity failure;
    assert not is_allowed(dc, (num => 0, den => 1))
      report "Null divisor accepted"
      severity failure;
    assert not is_allowed(dc, (num => 7, den => 2))
      report "Fractional value accepted on integer-only constraint"
      severity failure;

    dc := pll_divisor(pll_range(2, 128, 2), frac_l2_den => 3);
    assert is_allowed(dc, (num => 135, den => 8))
      report "On-grid fractional value refused"
      severity failure;
    assert not is_allowed(dc, (num => 27, den => 8))
      report "Fractional value with off-range integer part accepted"
      severity failure;
    assert not is_allowed(dc, (num => 1, den => 3))
      report "Off-grid fractional value accepted"
      severity failure;

    -- Multi-output exact solve

    cfg := pll_config(25_000_000,
                      pll_output(100_000_000),
                      pll_output(125_000_000),
                      pll_output(200_000_000));
    m := mapping_solve(topo_a_c, cfg);
    report to_string(cfg) & " on flexible block: " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 40, den => 1)
      and m.postdiv = 1 and m.vco_khz = 1_000_000
      report "Unexpected PLL core settings"
      severity failure;
    for i in 0 to 2 loop
      assert m.output(i).enabled and m.output(i).exact
        and m.output(i).hz = cfg.output(i).hz
        and m.output(i).port_index = i
        report "Unexpected output settings"
        severity failure;
    end loop;
    assert m.output(0).divisor = (num => 10, den => 1)
      and m.output(1).divisor = (num => 8, den => 1)
      and m.output(2).divisor = (num => 5, den => 1)
      report "Unexpected output divisors"
      severity failure;

    m2 := mapping_solve(topo_a_c, cfg);
    assert m2 = m
      report "Solver is not deterministic"
      severity failure;

    -- Unreachable rate

    cfg := pll_config(25_000_000, pll_output(1_000_000));
    m := mapping_solve(topo_a_c, cfg);
    report to_string(cfg) & " on flexible block: " & to_string(m)
      severity note;
    assert not m.valid
      report "Unreachable rate mapped"
      severity failure;

    -- Fractional divisor with tolerance

    cfg := pll_config(24_000_000,
                      pll_output(50_000_000,
                                 tolerance_ppm => 5000,
                                 allow_fractional => true));
    m := mapping_solve(topo_b_c, cfg);
    report to_string(cfg) & " on locked block: " & to_string(m)
      severity note;
    assert m.valid
      report "No fractional mapping found"
      severity failure;
    assert m.refdiv = 1 and m.fbdiv = (num => 35, den => 1)
      and m.vco_khz = 840_000
      report "Unexpected PLL core settings for fractional mapping"
      severity failure;
    assert m.output(0).enabled and not m.output(0).exact
      and m.output(0).port_index = 0
      and m.output(0).divisor = (num => 134, den => 8)
      and m.output(0).hz = 50_149_254
      report "Unexpected fractional output settings"
      severity failure;

    -- Same request without slack must fail

    cfg := pll_config(24_000_000,
                      pll_output(50_000_000,
                                 allow_fractional => true));
    m := mapping_solve(topo_b_c, cfg);
    report to_string(cfg) & " on locked block: " & to_string(m)
      severity note;
    assert not m.valid
      report "Inexact rate mapped as exact"
      severity failure;

    -- Output-to-port reordering

    cfg := pll_config(25_000_000,
                      pll_output(25_000_000),
                      pll_output(100_000_000));
    m := mapping_solve(topo_c_c, cfg);
    report to_string(cfg) & " on split-range block: " & to_string(m)
      severity note;
    assert m.valid
      report "No reordered mapping found"
      severity failure;
    assert m.vco_khz = 1_000_000
      report "Unexpected VCO rate for reordered mapping"
      severity failure;
    assert m.output(0).exact and m.output(0).port_index = 1
      and m.output(0).divisor = (num => 40, den => 1)
      report "Unexpected mapping for reordered output 0"
      severity failure;
    assert m.output(1).exact and m.output(1).port_index = 0
      and m.output(1).divisor = (num => 10, den => 1)
      report "Unexpected mapping for reordered output 1"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
