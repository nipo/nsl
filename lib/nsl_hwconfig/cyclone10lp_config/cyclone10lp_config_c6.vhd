package body cyclone10lp_config is

  -- fOUT to a global clock network on a -C6 part.
  function pll_constraints_get return pll_constraints
  is
  begin
    return pll_constraints'(
      out_max => 472_500_000);
  end function;

end package body;
