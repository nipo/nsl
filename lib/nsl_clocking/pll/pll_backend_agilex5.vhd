library ieee;
use ieee.std_logic_1164.all;

library nsl_hwconfig;
use nsl_hwconfig.agilex5_config.all;

use work.pll.all;

package body pll_backend is

  -- An Agilex 5 I/O PLL takes its reference from wherever the fitter
  -- routes it, and this abstraction models neither the choice
  -- between a fabric-feeding and an I/O bank PLL -- the fitter makes
  -- it from placement -- nor which network an output lands on.
  function pll_reference_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Agilex 5 PLL has no reference input named " & name
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT" or name = "IOPLL"
      report "Agilex 5 PLL has no implementation named " & name
        & ", expected IOPLL"
      severity failure;
    return 0;
  end function;

  function pll_routing_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Agilex 5 PLL has no output routing named " & name
      severity failure;
    return 0;
  end function;

  -- Seven post-scale counters C0 to C6, integer dividers from 1 to
  -- 510.  A fabric-feeding PLL in HVIO banks 6E to 6H only carries
  -- two of them, which the fitter reports rather than this model.
  --
  -- Each output shifts by eighths of a VCO period, the phase mux
  -- selecting the eighth and the counter preset, 1 to 256, delaying
  -- by whole VCO periods: out_clk_N_phase_shifts is the count of
  -- eighths, at most 7 + 8 * 255.
  constant agilex5_output_c : pll_output_topology_t := (
    divisor => pll_divisor(pll_range(1, 510)),
    phase_den => 0, phase_step_max => 0,
    phase_vco_den => 8, phase_vco_step_max => 2047);

  constant agilex5_output_none_c : pll_output_topology_t := (
    divisor => pll_divisor_unity_c,
    phase_den => 0, phase_step_max => 0,
    phase_vco_den => 0, phase_vco_step_max => 0);

  -- N pre-scale on the reference, 1 to 110, and M in the feedback, 4
  -- to 320, with the C counters hanging off the VCO itself: in
  -- direct compensation, the VCO runs at the PFD rate times M.
  -- Counter ranges come from table 2 of the Agilex 5 Clocking and
  -- PLL User Guide (813671), integer mode being the only one.
  --
  -- The PFD window, 10 to 325 MHz, and the VCO floor, 600 MHz, come
  -- from table 48 of the Agilex 5 Device Data Sheet (813918) and are
  -- common to every speed grade.  The VCO ceiling and the output
  -- ceiling move with the grade, so they come from nsl_hwconfig.
  constant agilex5_constraints_c : pll_constraints := pll_constraints_get;

  constant agilex5_topology_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 110)),
    fbdiv => pll_divisor(pll_range(4, 320)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 10_000,
    pfd_khz_max => 325_000,
    vco_khz_min => 600_000,
    vco_khz_max => agilex5_constraints_c.vco_khz_max,
    out_khz_max => agilex5_constraints_c.out_khz_max,
    output_count => 7,
    output => (0 to 6 => agilex5_output_c,
               others => agilex5_output_none_c));

  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
  begin
    assert implementation = 0
      report "Agilex 5 PLL has one implementation"
      severity failure;
    return agilex5_topology_c;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
