library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;

-- Backend-specific side of the PLL abstraction.
--
-- Package declaration is common, package body is provided per
-- backend and selected at build time.  Functions here are the entry
-- point for user code that needs to inspect a PLL realization:
-- pll_solve() is a pure deterministic function, the mapping it
-- returns is the one pll_multi implements for the same arguments.
--
-- The three *_id functions name the choices a divisor cannot
-- express.  Each backend defines its own vocabulary and fails
-- elaboration on a name it does not define, so a mistake is caught
-- where it is written rather than silently ignored.  The names a
-- backend accepts are documented in its body; every backend accepts
-- "DEFAULT", and 0 -- the value a config holds when nothing is
-- named -- is that default.
package pll_backend is

  -- Pin type the reference clock comes from.
  function pll_reference_id(name: string) return natural;

  -- Which block to use, when the target has competing ones.
  function pll_implementation_id(name: string) return natural;

  -- Clock network an output drives.
  function pll_routing_id(name: string) return natural;

  -- Topology of the PLL block targeted on the current backend.
  -- Competing blocks have their own divisors and frequency windows,
  -- hence the implementation argument.
  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t;

  -- Solve config against the current backend topology.
  function pll_solve(config: pll_config_t) return pll_mapping_t;

end package pll_backend;
