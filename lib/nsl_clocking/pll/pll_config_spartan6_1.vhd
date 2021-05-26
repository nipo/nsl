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
      return constraints'(400000000, 1000000000, 64, 128, "PLL");
    elsif mode = "MMCM" then
      report "MMCM unsupported on this part"
        severity failure;
      return constraints'(0, 0, 0, 0, "MMCM");
    else
      return constraints'(500000, 200000000, 32, 32, "DCM");
    end if;
  end function;

end package body;
