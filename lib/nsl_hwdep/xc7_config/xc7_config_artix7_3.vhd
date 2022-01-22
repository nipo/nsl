library nsl_data;
use nsl_data.text.all;

package body xc7_config is

  function pll_constraints_get(mode: pll_variant) return pll_constraints
  is
  begin
    if mode = PLL then
      return pll_constraints'(800000000, 2133000000, 64, 128, "PLL");
    else
      return pll_constraints'(600000000, 1600000000, 64, 128, "MCM");
    end if;
  end function;

end package body;
