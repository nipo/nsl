library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_hwconfig;

package body pll_config_series67 is

  function variant_is_known(name: string) return boolean
  is
  begin
    return name = "PLL" or name = "MMCM";
  end function;

  function variant_get(name : string) return pll_variant
  is
  begin
    if name = "MMCM" then
      return S7_MMCM;
    else
      return S7_PLL;
    end if;
  end function;
        
  function constraints_get(mode: pll_variant) return constraints
  is
    variable ret: nsl_hwconfig.xc7_config.pll_constraints;
  begin
    if mode = S7_MMCM then
      ret := nsl_hwconfig.xc7_config.pll_constraints_get(nsl_hwconfig.xc7_config.MMCM);
    elsif mode = S7_PLL then
      ret := nsl_hwconfig.xc7_config.pll_constraints_get(nsl_hwconfig.xc7_config.PLL);
    else
      report "Unsupported mode" severity failure;
    end if;

    return constraints'(
      fmin => ret.fmin,
      fmax => ret.fmax,
      pfd_min => ret.pfd_min,
      pfd_max => ret.pfd_max,
      in_div_max => ret.in_div_max,
      in_factor_min => ret.in_factor_min,
      in_factor_max => ret.in_factor_max,
      out_factor_max => ret.out_factor_max,
      mode => ret.mode
      );
  end function;

  function variant_id(name: string) return natural
  is
  begin
    if name = "DEFAULT" then
      return 0;
    end if;
    return pll_variant'pos(variant_get(name)) + 1;
  end function;

  function variant_of_id(id: natural) return pll_variant
  is
  begin
    if id = 0 then
      return variant_get("DEFAULT");
    end if;
    return pll_variant'val(id - 1);
  end function;

end package body;
