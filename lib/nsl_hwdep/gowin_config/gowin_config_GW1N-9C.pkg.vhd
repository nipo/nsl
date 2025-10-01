package body gowin_config is

  function iodelay_step_ps return real
  is
  begin
    return 25.0;
  end function;

  function device_name return string
  is
  begin
    return "GW1N-9C";
  end function;

  function internal_osc return string
  is
  begin
    return "osc";
  end function;

  function pll_type return string
  is
  begin
    return "rpll";
  end function;

  function pll_vco_fmin return real
  is
  begin
    return 400.0e6;
  end function;

  function pll_vco_fmax return real
  is
  begin
    return 900.0e6;
  end function;

  function pll_pfd_fmin return real
  is
  begin
    return 3.0e6;
  end function;

  function pll_pfd_fmax return real
  is
  begin
    return 400.0e6;
  end function;

end package body;
