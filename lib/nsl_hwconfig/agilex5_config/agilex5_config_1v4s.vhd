package body agilex5_config is

  -- fVCO and fOUT on -1V and -4S parts.
  function pll_constraints_get return pll_constraints
  is
  begin
    return pll_constraints'(
      vco_khz_max => 3_200_000,
      out_khz_max => 1_100_000);
  end function;

end package body;
