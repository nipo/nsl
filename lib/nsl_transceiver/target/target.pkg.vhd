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
  -- named clock source. The returned integer is consumed by the
  -- vendor transceiver_cluster entity to route the matching
  -- ref_clock_i signal to the correct primitive input. Elaboration
  -- fails if the name is not recognised by the target.
  --
  -- The vocabulary is the target's own: each body names the clock
  -- inputs its primitive actually has ("ref0" and "fabric" on
  -- GW5A, "gtrefclk0" and "stableclk" on the Xilinx GT backends).
  -- Names are deliberately not unified across vendors, because a
  -- design moving between two FPGAs needs a board-level decision
  -- about which physical clock feeds the cluster anyway. That
  -- decision, and so the clock name, belongs to the per-board
  -- configuration rather than to portable logic.
  function clock_id(name : string) return integer;

end package target;
