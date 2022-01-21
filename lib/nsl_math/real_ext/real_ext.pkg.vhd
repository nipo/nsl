library ieee;
use ieee.math_real.all;

package real_ext is

  type real_vector is array (integer range <>) of real;
  
  -- Error function
  function erf(x : real) return real;

  function frac(x : real) return real;

  function max(v : real_vector;
               default : real := -1.0e100) return real;
  function min(v : real_vector;
               default : real := 1.0e100) return real;

end package real_ext;

package body real_ext is

  -- this is implemented after Burmann series approximation
  -- Relative error is bound to 3.6127e-3 at x=+/-1.3796
  -- (all info taken from WP page).
  function erf(x : real) return real
  is
  begin
    return 2.0 / math_sqrt_pi
      * sign(x)
      * sqrt(1.0 - exp(-(x ** 2.0)))
      * (math_sqrt_pi / 2.0
         + 31.0 / 200.0 * exp(-(x ** 2.0))
         - 341.0 / 8000.0 * exp(-2.0 * (x ** 2.0)));
  end erf;
  
  function frac(x : real) return real
  is
  begin
    return x - floor(x);
  end function;

  function max(v : real_vector;
               default : real := -1.0e100) return real is
    variable ret : real := default;
  begin
    for i in v'range
    loop
      ret := realmax(v(i), ret);
    end loop;
    return ret;
  end function;
  
  function min(v : real_vector;
               default : real := 1.0e100) return real is
    variable ret : real := default;
  begin
    for i in v'range
    loop
      ret := realmin(v(i), ret);
    end loop;
    return ret;
  end function;

end package body real_ext;
