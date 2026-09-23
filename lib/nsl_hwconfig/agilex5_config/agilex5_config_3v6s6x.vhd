package body agilex5_config is

  -- fVCO and fOUT on -3V, -6S and -6X parts.
  function pll_constraints_get return pll_constraints
  is
  begin
    return pll_constraints'(
      vco_khz_max => 2_400_000,
      out_khz_max => 780_000);
  end function;

end package body;
