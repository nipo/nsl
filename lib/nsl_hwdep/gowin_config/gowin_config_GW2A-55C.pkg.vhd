package body gowin_config is

  function iodelay_step_ps return real
  is
  begin
    return 18;
  end function;

  function device_name return string
  is
  begin
    return "GW2A-55C";
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
    return 500.0e6;
  end function;

  function pll_vco_fmax return real
  is
  begin
    return 1250.0e6;
  end function;

  function pll_pfd_fmin return real
  is
  begin
    return 3.0e6;
  end function;

  function pll_pfd_fmax return real
  is
  begin
    return 500.0e6;
  end function;

  function pll_odiv_possibilities return ivec
  is
  begin
    return (2,4,8,16,32,48,64,80,96,112,128);
  end function;

end package body;
