library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library nsl_math;
use nsl_math.fixed.all;

package cordic is

  -- Scale of sin/cos couple after given number of steps.
  function sincos_scale(step_count : integer) return real;

  -- Angle to rotate for at given step.  This function may be used to
  -- build a constant table in an iterative implementation of the
  -- algorithm.
  function sincos_angle_delta(step : integer) return real;

  -- Pre-step to collapse angle in [-pi/2 .. pi/2]
  -- Involves no scaling
  procedure sincos_half_collapse(a_o: out ufixed; x_o, y_o : out sfixed;
                                 a_i: in ufixed; x_i, y_i : in sfixed);

  -- Pre-step to collapse angle in [-pi/4 .. pi/4]
  -- Involves no scaling
  procedure sincos_fourth_collapse(a_o: out ufixed; x_o, y_o : out sfixed;
                                   a_i: in ufixed; x_i, y_i : in sfixed);

  -- General step of cordic, where angle error is corrected by steps.
  procedure sincos_astep(step : in integer; rot : in ufixed;
                         a_o: out ufixed; x_o, y_o : out sfixed;
                         a_i: in ufixed; x_i, y_i : in sfixed);

  -- One step of cordic algorithm for sincos, at a given step.
  -- Angle is in full turns (radians / (2 * pi)).
  -- angle'left should be -1.
  procedure sincos_step(step : in integer;
                        a_o: out ufixed; x_o, y_o : out sfixed;
                        a_i: in ufixed; x_i, y_i : in sfixed);

  -- Probably not useful as-is for synthesis. It is more a reference
  -- algorithm for usage of the above functions, and allows to check
  -- results in simulation.
  procedure sincos(a_i : in ufixed; x_o, y_o : out sfixed;
                   scale : real := 1.0);
  
end package cordic;

package body cordic is

  function sincos_scale(step_count : integer) return real
  is
    variable acc : real;
  begin
    acc := 1.0;
    for i in 0 to step_count-1
    loop
      acc := acc * sqrt(1.0 + (2.0 ** real(-2 * i)));
    end loop;
    return 1.0 / acc;
  end function;

  function sincos_angle_delta(step : integer) return real
  is
  begin
    return arctan(2.0 ** real(-step)) / MATH_2_PI;
  end function;

  procedure sincos_half_collapse(a_o: out ufixed;
                                 x_o, y_o : out sfixed;
                                 a_i: in ufixed;
                                 x_i, y_i : in sfixed)
  is
    constant half: ufixed(a_i'range) := to_ufixed(0.5, a_i'left, a_i'right);
    variable am : std_ulogic_vector(1 downto 0) := to_suv(a_i(-1 downto -2));
  begin
    case am is
      when "01" | "10" =>
        a_o := a_i + half;
        x_o := - x_i;
        y_o := - y_i;
      when others =>
        a_o := a_i;
        x_o := x_i;
        y_o := y_i;
    end case;
  end procedure;

  procedure sincos_fourth_collapse(a_o: out ufixed;
                                   x_o, y_o : out sfixed;
                                   a_i: in ufixed;
                                   x_i, y_i : in sfixed)
  is
    constant fourth: ufixed(a_i'range) := to_ufixed(0.25, a_i'left, a_i'right);
    variable am : std_ulogic_vector(2 downto 0) := to_suv(a_i(-1 downto -3));
  begin
    case am  is
      when "001" | "010" =>
        a_o := a_i - fourth;
        x_o := - y_i;
        y_o := x_i;
      when "110" | "101" =>
        a_o := a_i + fourth;
        x_o := y_i;
        y_o := - x_i;
      when others =>
        a_o := a_i;
        x_o := x_i;
        y_o := y_i;
    end case;
  end procedure;

  procedure sincos_astep(step : in integer;
                         rot : in ufixed;
                         a_o: out ufixed;
                         x_o, y_o : out sfixed;
                         a_i: in ufixed;
                         x_i, y_i : in sfixed)
  is
    constant dy : sfixed(x_i'range) := shr(y_i, step);
    constant dx : sfixed(y_i'range) := shr(x_i, step);
  begin
    if a_i(a_i'left) = '1' then
      a_o := a_i + rot;
      x_o := x_i + dy;
      y_o := y_i - dx;
    else
      a_o := a_i - rot;
      x_o := x_i - dy;
      y_o := y_i + dx;
    end if;
  end procedure;

  -- Generalization of sincos_steps with internal constant lookup
  procedure sincos_step(step : in integer;
                        a_o: out ufixed; x_o, y_o : out sfixed;
                        a_i: in ufixed; x_i, y_i : in sfixed)
  is
  begin
    case step is
      when -2 =>
        sincos_half_collapse(a_o, x_o, y_o, a_i, x_i, y_i);

      when -1 =>
        sincos_fourth_collapse(a_o, x_o, y_o, a_i, x_i, y_i);

      when others =>
        sincos_astep(step,
                     to_ufixed(sincos_angle_delta(step), a_i'left, a_i'right),
                     a_o, x_o, y_o, a_i, x_i, y_i);
    end case;
  end procedure;

  procedure sincos(a_i : in ufixed;
                   x_o, y_o : out sfixed;
                   scale : real := 1.0)
  is
    constant step_count : integer := 2 * nsl_math.arith.max(-x_o'right, -y_o'right);
    constant init_scale : real := sincos_scale(step_count);

    -- Only handle saturation once at the end, use one more bit for
    -- intermediate calculation
    variable a, a_n : ufixed(-1 downto a_i'right);
    variable x, x_n : sfixed(x_o'left+1 downto -step_count/2);
    variable y, y_n : sfixed(y_o'left+1 downto -step_count/2);
  begin
    a := resize(a_i, a'left, a'right);
    -- Rather than multiplying by scaling factor, just insert it ahead of time.
    x := to_sfixed(init_scale * scale, x'left, x'right);
    y := to_sfixed(0.0, y'left, y'right);
    
    for i in -2 to step_count-1
    loop
      sincos_step(i, a_n, x_n, y_n, a, x, y);
      a := a_n;
      x := x_n;
      y := y_n;
    end loop;
    
    x_o := resize_saturate(x, x_o'left, x_o'right);
    y_o := resize_saturate(y, y_o'left, y_o'right);
  end procedure;

end package body cordic;
