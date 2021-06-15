library nsl_data;
use nsl_data.text.all;

package body pll_config_series67 is

  function variant_get(hw_variant : string)
    return pll_variant
  is
  begin
    if strfind(hw_variant, "type=mmcm", ',') then
      return S7_MMCM;
    else
      return S7_PLL;
    end if;
  end function;

  function constraints_get(mode: string) return constraints
  is
  begin
    if mode = "PLL" then
      return constraints'(800000000, 1600000000, 64, 128, "PLL");
    elsif mode = "MMCM" then
      return constraints'(600000000, 1200000000, 64, 128, "MCM");
    else
      report "DCM unsupported on this part"
        severity failure;
      return constraints'(0, 0, 0, 0, "DCM");
    end if;
  end function;

end package body;
