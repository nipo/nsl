library nsl_data;
use nsl_data.text.all;

package body pll_config_series67 is

  function variant_get(hw_variant : string)
    return pll_variant
  is
  begin
    if strfind(hw_variant, "type=dcm", ',') then
      return S6_DCM;
    else
      return S6_PLL;
    end if;
  end function;

  function constraints_get(mode: string) return constraints
  is
  begin
    if mode = "PLL" then
      return constraints'(400000000, 1080000000, 64, 128, "PLL");
    elsif mode = "MMCM" then
      assert false
        report "MMCM unsupported on this part"
        severity failure;
    else
      return constraints'(500000, 375000000, 32, 32, "DCM");
    end if;
  end function;

end package body;
