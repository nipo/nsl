package body gowin_config is

  function iodelay_step_ps return real
  is
  begin
    return 12.5;
  end function;

  function device_name return string
  is
  begin
    return "GW5A-15A";
  end function;

  function internal_osc return string
  is
  begin
    return "osca";
  end function;

  function pll_type return string
  is
  begin
    return "pll";
  end function;

  function pll_vco_fmin return real
  is
  begin
    return 700.0e6;
  end function;

  function pll_vco_fmax return real
  is
  begin
    return 1400.0e6;
  end function;

  function pll_pfd_fmin return real
  is
  begin
    return 19.0e6;
  end function;

  function pll_pfd_fmax return real
  is
  begin
    return 81.25e6;
  end function;

  function pll_odiv_possibilities return ivec
  is
  begin
    return (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128);
  end function;

end package body;
