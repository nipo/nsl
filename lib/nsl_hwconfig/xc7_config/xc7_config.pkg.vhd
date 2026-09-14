library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package xc7_config is

  -- What one clock manager of this part, at this speed grade, can do.
  --
  -- fmin/fmax is the VCO locking window in Hz.  A block with no VCO
  -- states the window of its synthesized output there instead.
  --
  -- pfd_min/pfd_max is the phase detector window, in Hz, that the
  -- reference divided by the input divider has to land in.  A block
  -- with no phase detector on the modeled path leaves it open.
  --
  -- in_div_max is the input divider ceiling, in_factor_min and
  -- in_factor_max the feedback factor bounds -- a Series-7 clock
  -- manager refuses to multiply by one -- and out_factor_max the
  -- per-output divider ceiling.
  type pll_constraints is
  record
    fmin, fmax : integer;
    pfd_min, pfd_max : integer;
    in_div_max : integer;
    in_factor_min, in_factor_max : integer;
    out_factor_max : integer;
    mode : string(1 to 3);
  end record;
  
  type pll_variant is (
    MMCM,
    PLL
    );

  function pll_constraints_get(mode: pll_variant) return pll_constraints;

end package;
