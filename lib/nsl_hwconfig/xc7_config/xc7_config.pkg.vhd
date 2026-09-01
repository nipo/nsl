library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package xc7_config is

  type pll_constraints is
  record
    fmin, fmax : integer;
    in_factor_max, out_factor_max : integer;
    mode : string(1 to 3);
  end record;
  
  type pll_variant is (
    MMCM,
    PLL
    );

  function pll_constraints_get(mode: pll_variant) return pll_constraints;

end package;
