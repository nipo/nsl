library nsl_data;
use nsl_data.text.all;

package body xc7_config is

  function pll_constraints_get(mode: pll_variant) return pll_constraints
  is
  begin
    if mode = PLL then
      return pll_constraints'(
        fmin => 800000000,
        fmax => 1600000000,
        pfd_min => 19000000,
        pfd_max => 450000000,
        in_div_max => 56,
        in_factor_min => 2,
        in_factor_max => 64,
        out_factor_max => 128,
        mode => "PLL");
    else
      return pll_constraints'(
        fmin => 600000000,
        fmax => 1200000000,
        pfd_min => 10000000,
        pfd_max => 450000000,
        in_div_max => 106,
        in_factor_min => 2,
        in_factor_max => 64,
        out_factor_max => 128,
        mode => "MCM");
    end if;
  end function;

end package body;
