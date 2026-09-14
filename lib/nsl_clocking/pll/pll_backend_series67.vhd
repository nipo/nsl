library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;
use work.pll_config_series67.all;

package body pll_backend is

  -- A Xilinx clock manager takes its reference from routing, and the
  -- output buffers are the tool's business, so neither is named
  -- here.  What a design does pick is the block: a Spartan-6 has a
  -- PLL and a DCM, a Series-7 part a PLL and an MMCM.
  function pll_reference_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Series-6/7 PLL has no reference input named " & name
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT" or variant_is_known(name)
      report "This part has no clock manager named " & name
      severity failure;
    return variant_id(name);
  end function;

  function pll_routing_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Series-6/7 PLL has no output routing named " & name
      severity failure;
    return 0;
  end function;

  -- Built from the per-part frequency and divider limits in
  -- nsl_hwconfig.  What those limits do not state is a property of
  -- the block rather than of the die, so it lands here: how many
  -- outputs it carries and how finely it shifts one.
  --
  -- A PLL or an MMCM delays an output by whole and eighth VCO cycles,
  -- which the tools recover from CLKOUTx_PHASE by scaling the degrees
  -- back by the output divisor.  The whole cycles sit in a six-bit
  -- field and the eighths in a three-bit one, so the delay stops at
  -- 511 eighths: with an output divisor above 85 that is short of
  -- three quarters of an output cycle.
  --
  -- A DCM has no VCO: its multiplier feeds the output divider
  -- directly, and the "VCO" window is the DFS output window.  Its
  -- phase shift is a fraction of the input period and common to every
  -- output, which is not what a per-output phase means, so none is
  -- offered here.
  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
    constant variant_c : pll_variant := variant_of_id(implementation);
    constant bounds_c : constraints := constraints_get(variant_c);
    constant shifting_output_c : pll_output_topology_t := (
      divisor => pll_divisor(pll_range(1, bounds_c.out_factor_max)),
      phase_den => 0,
      phase_step_max => 0,
      phase_vco_den => 8,
      phase_vco_step_max => 511);
    constant plain_output_c : pll_output_topology_t := (
      divisor => pll_divisor(pll_range(1, bounds_c.out_factor_max)),
      phase_den => 0,
      phase_step_max => 0,
      phase_vco_den => 0,
      phase_vco_step_max => 0);
    variable ret : pll_topology_t;
  begin
    ret.refdiv := pll_divisor(pll_range(1, bounds_c.in_div_max));
    ret.fbdiv := pll_divisor(pll_range(bounds_c.in_factor_min,
                                       bounds_c.in_factor_max));
    ret.postdiv := pll_divisor_unity_c;
    ret.pfd_khz_min := bounds_c.pfd_min / 1000;
    ret.pfd_khz_max := bounds_c.pfd_max / 1000;
    ret.vco_khz_min := bounds_c.fmin / 1000;
    ret.vco_khz_max := bounds_c.fmax / 1000;
    ret.output := (others => (divisor => pll_divisor_unity_c,
                              phase_den => 0,
                              phase_step_max => 0,
                              phase_vco_den => 0,
                              phase_vco_step_max => 0));

    if bounds_c.mode = "DCM" then
      ret.output_count := 1;
      ret.output(0) := plain_output_c;
    elsif bounds_c.mode = "MCM" then
      -- An MMCM carries a seventh output, on a divider of its own.
      ret.output_count := 7;
      for i in 0 to 6 loop
        ret.output(i) := shifting_output_c;
      end loop;
    else
      ret.output_count := 6;
      for i in 0 to 5 loop
        ret.output(i) := shifting_output_c;
      end loop;
    end if;

    return ret;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
