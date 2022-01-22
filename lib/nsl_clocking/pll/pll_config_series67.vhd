library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package pll_config_series67 is

  type constraints is
  record
    fmin, fmax : integer;
    in_factor_max, out_factor_max : integer;
    mode : string(1 to 3);
  end record;
  
  type pll_variant is (
    S6_PLL,
    S7_MMCM,
    S7_PLL,
    S6_DCM
    );

  function variant_get(hw_variant : string) return pll_variant;
  function constraints_get(mode: pll_variant) return constraints;

end package;
