library ieee;
use ieee.std_logic_1164.all;

package agilex5_config is

  -- What one I/O PLL of this part, at this speed grade, can do.
  --
  -- vco_khz_max is the top of the VCO window and out_khz_max the highest
  -- rate a C counter hands to the core, both in kHz, since the VCO
  -- ceiling does not fit an integer in Hz.  They are the I/O PLL
  -- figures table 48 of the Agilex 5 Device Data Sheet (813918)
  -- states per speed grade: the PFD window, the VCO floor and the N,
  -- M and C counter ranges are common to the family and are stated
  -- by whoever models the block rather than here.
  type pll_constraints is
  record
    vco_khz_max: integer;
    out_khz_max: integer;
  end record;

  function pll_constraints_get return pll_constraints;

end package;
