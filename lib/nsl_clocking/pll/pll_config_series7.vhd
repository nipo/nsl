library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_hwdep;

package body pll_config_series67 is

  function variant_get(hw_variant : string) return pll_variant
  is
  begin
    if hw_variant = "MMCM" then
      return S7_MMCM;
    else
      return S7_PLL;
    end if;
  end function;
        
  function constraints_get(mode: pll_variant) return constraints
  is
    variable ret: nsl_hwdep.xc7_config.pll_constraints;
  begin
    if mode = S7_MMCM then
      ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.MMCM);
    elsif mode = S7_PLL then
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

end package body;
