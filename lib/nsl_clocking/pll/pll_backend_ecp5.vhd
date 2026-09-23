library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;

package body pll_backend is

  -- EHXPLLL takes its reference from fabric routing whatever the pin
  -- is, and the part has one PLL block and one clock network as far
  -- as this abstraction is concerned.
  function pll_reference_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "ECP5 PLL has no reference input named " & name
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT" or name = "EHXPLLL"
      report "ECP5 PLL has no implementation named " & name
        & ", expected EHXPLLL"
      severity failure;
    return 0;
  end function;

  function pll_routing_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "ECP5 PLL has no output routing named " & name
      severity failure;
    return 0;
  end function;

  -- EHXPLLL with feedback through the CLKOP divider, CLKOP reserved
  -- for the loop: with CLKFB_DIV pinned to 1 and CLKOP_DIV carrying
  -- the whole multiplication, the VCO runs at pfd * CLKOP_DIV and
  -- CLKOP itself at pfd rate, which keeps the feedback slow whatever
  -- the multiplier.  User outputs are CLKOS, CLKOS2 and CLKOS3, each
  -- an integer divider off the VCO.  Phase adjustment is not
  -- modeled.
  constant ecp5_output_c : pll_output_topology_t := (
    divisor => pll_divisor(pll_range(1, 128)),
    phase_den => 0, phase_step_max => 0,
    phase_vco_den => 0, phase_vco_step_max => 0);

  constant ecp5_topology_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 128)),
    fbdiv => pll_divisor(pll_range(1, 128)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 8_000,
    pfd_khz_max => 400_000,
    vco_khz_min => 400_000,
    vco_khz_max => 800_000,
    -- No output ceiling stated: an output is bounded by the VCO
    -- window and its own divider alone.
    out_khz_max => 0,
    output_count => 3,
    output => (0 | 1 | 2 => ecp5_output_c,
               others => (divisor => pll_divisor_unity_c,
                          phase_den => 0, phase_step_max => 0,
                          phase_vco_den => 0, phase_vco_step_max => 0)));

  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
  begin
    assert implementation = 0
      report "ECP5 PLL has one implementation"
      severity failure;
    return ecp5_topology_c;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
