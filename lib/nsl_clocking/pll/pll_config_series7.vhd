library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_hwdep;

package body pll_config_series67 is

  function variant_get(hw_variant : string) return pll_variant
  is
  begin
    if nsl_hwdep.xc7_config.pll_variant_get(hw_variant) == nsl_hwdep.xc7_config.PLL then
      return S7_PLL;
    else
      return S7_MMCM;
    end if;
  end function;
        
  function constraints_get(mode: pll_variant) return constraints
  is
    variable ret: nsl_hwdep.xc7_config.pll_constraints;
  begin
    if pll_variant == S7_MMCM then
      ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.MMCM);
    elsif pll_variant == S6_PLL then
      ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.PLL);
    else
      report "Unsupported mode" severity failure;
    end if;

    return constraints'(
      fmin => ret.fmin,
      fmax => ret.fmax,
      in_factor_max => ret.in_factor_max,
      out_factor_max => ret.out_factor_max,
      mode => ret.mode
      );
  end function;

end package;
