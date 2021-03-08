library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_data, nsl_simulation, nsl_color;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_color.rgb.all;

entity tb is
end tb;

architecture arch of tb is
begin

  Test0: process
    variable c : rgb24;
  begin
    c := rgb24_from_hsv(0.0, 1.0, 1.0);
    assert_equal("red r", c.r, x"FF", note);
    assert_equal("red g", c.g, x"00", note);
    assert_equal("red b", c.b, x"00", note);
    c := rgb24_from_hsv(2.0*MATH_PI_OVER_3, 1.0, 1.0);
    assert_equal("green r", c.r, x"00", note);
    assert_equal("green g", c.g, x"FF", note);
    assert_equal("green b", c.b, x"00", note);
    c := rgb24_from_hsv(4.0*MATH_PI_OVER_3, 1.0, 1.0);
    assert_equal("blue r", c.r, x"00", note);
    assert_equal("blue g", c.g, x"00", note);
    assert_equal("blue b", c.b, x"FF", note);

    c := rgb24_from_hsv(0.0, 1.0, 0.5);
    assert_equal("red r", c.r, x"80", note);
    assert_equal("red g", c.g, x"00", note);
    assert_equal("red b", c.b, x"00", note);
    c := rgb24_from_hsv(2.0*MATH_PI_OVER_3, 1.0, 0.5);
    assert_equal("green r", c.r, x"00", note);
    assert_equal("green g", c.g, x"80", note);
    assert_equal("green b", c.b, x"00", note);
    c := rgb24_from_hsv(4.0*MATH_PI_OVER_3, 1.0, 0.5);
    assert_equal("blue r", c.r, x"00", note);
    assert_equal("blue g", c.g, x"00", note);
    assert_equal("blue b", c.b, x"80", note);

    for i in 0 to 119
    loop
      c := rgb24_from_hsv(real(i) * MATH_2_PI / 120.0, 1.0, 1.0);
      log_debug("HSV("&to_string(i*3)&", 1.0, 1.0) = RGB("
                &to_string(to_integer(c.r))&", "
                &to_string(to_integer(c.g))&", "
                &to_string(to_integer(c.b))&")");
    end loop;

    for i in 0 to 119
    loop
      c := rgb24_from_hsv(real(i) * MATH_2_PI / 120.0, 0.5, 1.0);
      log_debug("HSV("&to_string(i*3)&", 0.5, 1.0) = RGB("
                &to_string(to_integer(c.r))&", "
                &to_string(to_integer(c.g))&", "
                &to_string(to_integer(c.b))&")");
    end loop;

    for i in 0 to 119
    loop
      c := rgb24_from_hsv(real(i) * MATH_2_PI / 120.0, 1.0, 0.5);
      log_debug("HSV("&to_string(i*3)&", 1.0, 0.5) = RGB("
                &to_string(to_integer(c.r))&", "
                &to_string(to_integer(c.g))&", "
                &to_string(to_integer(c.b))&")");
    end loop;

    for i in 0 to 119
    loop
      c := rgb24_from_hsv(real(i) * MATH_2_PI / 120.0, 0.5, 0.5);
      log_debug("HSV("&to_string(i*3)&", 0.5, 0.5) = RGB("
                &to_string(to_integer(c.r))&", "
                &to_string(to_integer(c.g))&", "
                &to_string(to_integer(c.b))&")");
    end loop;

    wait;
  end process;

end;
