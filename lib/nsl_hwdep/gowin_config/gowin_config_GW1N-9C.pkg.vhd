package body gowin_config is

  function iodelay_step_ps return integer
  is
  begin
    return 25;
  end function;

  function device_name return string
  is
  begin
    return "GW1N-9C";
  end function;

  function internal_osc return string
  is
  begin
    return "osch";
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

end package body;
