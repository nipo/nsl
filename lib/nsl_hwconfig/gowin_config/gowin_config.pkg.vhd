package gowin_config is

  type ivec is array(integer range <>) of integer;
  
  function iodelay_step_ps return real;
  function device_name return string;
  function internal_osc return string;
  function pll_type return string;
  function pll_vco_fmin return real;
  function pll_vco_fmax return real;
  function pll_pfd_fmin return real;
  function pll_pfd_fmax return real;
  function pll_odiv_possibilities return ivec;
  
end package;
