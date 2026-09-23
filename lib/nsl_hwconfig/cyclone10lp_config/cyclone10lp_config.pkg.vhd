library ieee;
use ieee.std_logic_1164.all;

package cyclone10lp_config is

  -- What one PLL of this part, at this speed grade, can do.
  --
  -- out_max is the highest rate an output drives onto a global clock
  -- network, in Hz.  It is the only PLL figure table 21 of the Intel
  -- Cyclone 10 LP Device Datasheet (C10LP51002) states per speed
  -- grade: the phase detector window, the oscillator window and the
  -- N, M and C counter ranges are common to the family and are
  -- stated by whoever models the block rather than here.
  type pll_constraints is
  record
    out_max: integer;
  end record;

  function pll_constraints_get return pll_constraints;

end package;
