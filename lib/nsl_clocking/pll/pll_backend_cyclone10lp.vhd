library ieee;
use ieee.std_logic_1164.all;

library nsl_hwconfig;
use nsl_hwconfig.cyclone10lp_config.all;

use work.pll.all;

package body pll_backend is

  -- A Cyclone 10 LP PLL takes its reference from fabric routing
  -- whatever the pin is, carries one kind of block, and this
  -- abstraction does not model which global network an output lands
  -- on.
  function pll_reference_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Cyclone 10 LP PLL has no reference input named " & name
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT" or name = "ALTPLL"
      report "Cyclone 10 LP PLL has no implementation named " & name
        & ", expected ALTPLL"
      severity failure;
    return 0;
  end function;

  function pll_routing_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Cyclone 10 LP PLL has no output routing named " & name
      severity failure;
    return 0;
  end function;

  -- Five post-scale counters C0 to C4, each an integer divider, each
  -- reaching 512 at the 50% duty cycle this abstraction always asks
  -- for.  A non-50% duty cycle would cap them at 256, and there is
  -- no way to request one here.
  --
  -- Phase shift is not modeled.  ALTPLL states a shift in
  -- picoseconds and lands it on the eighth of a VCO period nearest
  -- to it, so an exact fraction of an output cycle would only come
  -- out exact when the VCO rate is known -- and here the vendor, not
  -- this solver, settles the VCO.  A config asking for a phase fails
  -- elaboration rather than getting an approximation.
  constant cyclone10lp_output_c : pll_output_topology_t := (
    divisor => pll_divisor(pll_range(1, 512)),
    phase_den => 0, phase_step_max => 0,
    phase_vco_den => 0, phase_vco_step_max => 0);

  constant cyclone10lp_output_none_c : pll_output_topology_t := (
    divisor => pll_divisor_unity_c,
    phase_den => 0, phase_step_max => 0,
    phase_vco_den => 0, phase_vco_step_max => 0);

  -- N pre-scale on the reference and M in the feedback, both 1 to
  -- 512, with the C counters hanging off the node the feedback is
  -- taken from: the rate the C counters divide is the PFD rate times
  -- M, and an output is that over its own C.
  --
  -- The oscillator itself runs a step ahead of that node, behind the
  -- VCO post-scale counter K, which either passes it through or
  -- halves it on the way to the C counters and to the feedback
  -- alike.  K is not a divisor this abstraction chooses and not one
  -- it can place: it takes no rate of its own, it only lets the
  -- oscillator sit an octave above the node when that node would
  -- otherwise be too slow to oscillate.  So it is carried in the
  -- window rather than in a divisor, and postdiv states unity.
  --
  -- Windows come from table 21 of the Intel Cyclone 10 LP Device
  -- Datasheet (C10LP51002), the same for every speed grade: PFD
  -- input 5 to 325 MHz and oscillator 600 to 1300 MHz.  The
  -- oscillator window maps onto the node the C counters see as 600
  -- to 1300 with K = 1 and 300 to 650 with K = 2, which overlap into
  -- a contiguous 300 to 1300.  That is the window stated here, and
  -- vco_khz in a mapping is therefore the rate at the C counters --
  -- the one Quartus names "Nominal VCO frequency" in the PLL Summary
  -- of its compilation report, alongside the K it settled on.
  --
  -- The same table states an output ceiling, and that is the one
  -- figure there which moves with the speed grade, so it comes from
  -- nsl_hwconfig rather than from here.  It bounds the rate onto a
  -- global clock network, the only destination this abstraction
  -- models; driving a pin instead would allow 472.5 MHz whatever the
  -- grade.
  constant cyclone10lp_constraints_c : pll_constraints := pll_constraints_get;

  constant cyclone10lp_topology_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 512)),
    fbdiv => pll_divisor(pll_range(1, 512)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 5_000,
    pfd_khz_max => 325_000,
    vco_khz_min => 300_000,
    vco_khz_max => 1_300_000,
    out_khz_max => cyclone10lp_constraints_c.out_max / 1000,
    output_count => 5,
    output => (0 to 4 => cyclone10lp_output_c,
               others => cyclone10lp_output_none_c));

  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
  begin
    assert implementation = 0
      report "Cyclone 10 LP PLL has one implementation"
      severity failure;
    return cyclone10lp_topology_c;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
