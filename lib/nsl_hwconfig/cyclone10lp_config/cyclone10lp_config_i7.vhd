package body cyclone10lp_config is

  -- fOUT to a global clock network on a -I7 part.
  function pll_constraints_get return pll_constraints
  is
  begin
    return pll_constraints'(
      out_max => 450_000_000);
  end function;

end package body;
