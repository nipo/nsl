library nsl_data;
use nsl_data.text.all;

package body xc6_config is

  function pll_constraints_get(mode: pll_variant) return pll_constraints
  is
  begin
    if mode = PLL then
      return pll_constraints'(400000000, 1000000000, 64, 128, "PLL");
    else
      return pll_constraints'(500000, 200000000, 32, 32, "DCM");
    end if;
  end function;

  function iodelay2_tap_ps return integer
  is
  begin
    return 58;
  end function;     

end package body;
