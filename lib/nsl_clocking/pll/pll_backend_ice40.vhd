library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;

package body pll_backend is

  -- The reference pin type picks the primitive: a pad reference is
  -- SB_PLL40_PAD, whose input must be the package pin itself, and a
  -- core reference is SB_PLL40_CORE, fed from fabric.  Pad is the
  -- default, as it was for pll_basic.
  constant reference_pad_c : natural := 0;
  constant reference_core_c : natural := 1;

  -- Outputs leave the block either on the global network or into
  -- fabric routing.  Global is the default.
  constant routing_global_c : natural := 0;
  constant routing_core_c : natural := 1;

  function pll_reference_id(name: string) return natural
  is
  begin
    if name = "DEFAULT" or name = "PAD" then
      return reference_pad_c;
    elsif name = "CORE" then
      return reference_core_c;
    end if;
    assert false
      report "iCE40 PLL has no reference input named " & name
        & ", expected PAD or CORE"
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "iCE40 PLL has one implementation, SB_PLL40, "
        & "selected by its reference input, not by " & name
      severity failure;
    return 0;
  end function;

  function pll_routing_id(name: string) return natural
  is
  begin
    if name = "DEFAULT" or name = "GLOBAL" then
      return routing_global_c;
    elsif name = "CORE" then
      return routing_core_c;
    end if;
    assert false
      report "iCE40 PLL has no output routing named " & name
        & ", expected GLOBAL or CORE"
      severity failure;
    return 0;
  end function;

  -- SB_PLL40 in SIMPLE feedback mode: one output, reference divider
  -- DIVR (1..16), feedback DIVF (1..128, the full 7-bit field is
  -- usable in this mode), power-of-two output divider 2**DIVQ with
  -- DIVQ 1..6.  No fractional part, no modeled phase.
  constant ice40_topology_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 16)),
    fbdiv => pll_divisor(pll_range(1, 128)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 10_000,
    pfd_khz_max => 133_000,
    vco_khz_min => 533_000,
    vco_khz_max => 1_066_000,
    output_count => 1,
    output => (0 => (divisor => pll_divisor(pll_range(2, 2),
                                            pll_range(4, 4),
                                            pll_range(8, 8),
                                            pll_range(16, 16),
                                            pll_range(32, 32),
                                            pll_range(64, 64)),
                     phase_den => 0, phase_step_max => 0,
                     phase_vco_den => 0, phase_vco_step_max => 0),
               others => (divisor => pll_divisor_unity_c,
                          phase_den => 0, phase_step_max => 0,
                          phase_vco_den => 0, phase_vco_step_max => 0)));

  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
  begin
    assert implementation = 0
      report "iCE40 PLL has one implementation"
      severity failure;
    return ice40_topology_c;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
