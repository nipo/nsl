library nsl_data;
use nsl_data.text.all;

package body xc6_config is

  function pll_constraints_get(mode: pll_variant) return pll_constraints
  is
  begin
    if mode = PLL then
      return pll_constraints'(
        fmin => 400000000,
        fmax => 1000000000,
        pfd_min => 19000000,
        pfd_max => 400000000,
        in_div_max => 52,
        in_factor_min => 1,
        in_factor_max => 74,
        out_factor_max => 128,
        mode => "PLL");
    else
      -- A DCM has no VCO and no phase detector: the multiplier feeds
      -- the output divider straight.  What the window here holds is
      -- the synthesizer's output range, checked against the
      -- multiplier's product, which is at or above the rate actually
      -- synthesized; the check is therefore on the safe side.  The
      -- phase detector window holds the input range instead, the
      -- input divider being the halving switch.
      return pll_constraints'(
        fmin => 5000000,
        fmax => 333000000,
        pfd_min => 5000000,
        pfd_max => 250000000,
        in_div_max => 2,
        in_factor_min => 2,
        in_factor_max => 32,
        out_factor_max => 32,
        mode => "DCM");
    end if;
  end function;

  function iodelay2_tap_ps return integer
  is
  begin
    return 46;
  end function;

end package body;
