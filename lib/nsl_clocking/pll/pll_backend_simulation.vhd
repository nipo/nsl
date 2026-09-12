library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;

package body pll_backend is

  -- An idealized block has no pin types, no competing implementation
  -- and one clock network, so "DEFAULT" is the whole vocabulary.  A
  -- source naming a hardware-specific choice does not elaborate here:
  -- the choice would have no meaning, and silently accepting it would
  -- hide the difference between what is simulated and what is built.
  function pll_reference_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Simulation PLL has no reference input named " & name
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Simulation PLL has no implementation named " & name
      severity failure;
    return 0;
  end function;

  function pll_routing_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Simulation PLL has no output routing named " & name
      severity failure;
    return 0;
  end function;

  -- Idealized PLL block.  Constraints are kept in the range of
  -- typical hardware blocks so that a design validated in simulation
  -- stands a chance of mapping on an actual backend.
  constant simulation_output_c : pll_output_topology_t := (
    divisor => pll_divisor(pll_range(1, 256), frac_l2_den => 8),
    phase_den => 720, phase_vco_den => 0);

  constant simulation_topology_c : pll_topology_t := (
    refdiv => pll_divisor(pll_range(1, 64)),
    fbdiv => pll_divisor(pll_range(1, 1024)),
    postdiv => pll_divisor_unity_c,
    pfd_khz_min => 4_000,
    pfd_khz_max => 100_000,
    vco_khz_min => 400_000,
    vco_khz_max => 1_600_000,
    output_count => 8,
    output => (others => simulation_output_c));

  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
  begin
    assert implementation = 0
      report "Simulation PLL has one implementation"
      severity failure;
    return simulation_topology_c;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
