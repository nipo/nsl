library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package pll_config_series67 is

  -- Mirror of the nsl_hwconfig record, so that the backend does not
  -- have to name the family package.
  type constraints is
  record
    fmin, fmax : integer;
    pfd_min, pfd_max : integer;
    in_div_max : integer;
    in_factor_min, in_factor_max : integer;
    out_factor_max : integer;
    mode : string(1 to 3);
  end record;
  
  type pll_variant is (
    S6_PLL,
    S7_MMCM,
    S7_PLL,
    S6_DCM
    );

  -- Name of a variant, as pll_implementation_id() takes it.  Only
  -- the names the target family actually has are known: a Spartan-6
  -- has no MMCM, a Series-7 part no DCM.
  function variant_is_known(name: string) return boolean;
  function variant_get(name : string) return pll_variant;
  function constraints_get(mode: pll_variant) return constraints;

  -- Opaque id a pll_config_t carries: 0 is the family's default
  -- block, anything else designates one variant.
  function variant_id(name: string) return natural;
  function variant_of_id(id: natural) return pll_variant;

end package;
