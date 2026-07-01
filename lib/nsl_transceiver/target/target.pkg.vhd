library ieee;
use ieee.std_logic_1164.all;

-- Target-specific hardware-abstraction functions for
-- nsl_transceiver. This package declaration is target-agnostic;
-- exactly one target-specific body is compiled into the working
-- library based on the project's hwdep / target_part variables.
--
-- The body of this package acts as the vendor selector for
-- nsl_transceiver, in the same pattern used by
-- nsl_clocking.pll_config_series67 (declaration) /
-- pll_config_series7.vhd (backend-specific body).
package target is

  -- Return an implementation-defined integer identifier for the
  -- named clock source. The name is a portable string ("ref0",
  -- "ref1", "fabric", ...) whose meaning is stable across
  -- targets; the returned integer is consumed by the vendor
  -- transceiver_group entity to route the matching ref_clock_i
  -- signal to the correct primitive input. Elaboration fails if
  -- the name is not recognised by the target.
  function clock_id(name : string) return integer;

end package target;
