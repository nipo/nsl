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

  -- One step of cordic algorithm for sincos, at a given step.
  -- Angle is in full turns (radians / (2 * pi)).
  -- angle'left should be -1.
  procedure sincos_step(angle: inout ufixed;
                        x, y : inout sfixed;
                        step : in integer);

  -- Probably not useful as-is for synthesis. It is more a reference
  -- algorithm for usage of the above functions, and allows to check
  -- results in simulation.
  procedure sincos(angle_i : in ufixed;
                   x_o, y_o : out sfixed;
                   step_count : integer;
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

  procedure sincos_astep(angle: inout ufixed;
                         x, y : inout sfixed;
                         step : in integer)
  is
    constant rot : ufixed(angle'range)
      := to_ufixed(sincos_angle_delta(step), angle'left, angle'right);
    constant dy : sfixed(x'range) := shr(y, step);
    constant dx : sfixed(y'range) := shr(x, step);
  begin
    if angle(angle'left) = '1' then
      angle := angle + rot;
      x := x - dy;
      y := y + dx;
    else
      angle := angle - rot;
      x := x + dy;
      y := y - dx;
    end if;
  end procedure;

  procedure sincos_step(angle: inout ufixed;
                        x, y : inout sfixed;
                        step : in integer)
  is
    constant x_i: sfixed(x'range) := x;
    constant y_i: sfixed(y'range) := y;
  begin
    case step is
      when -2 =>
        -- Pre-step to collapse angle in [-pi/2 .. pi/2]
        -- Involves no scaling
        if angle(-1) /= angle(-2) then
          angle := angle + to_ufixed(0.5, angle'left, angle'right);
          x := - x_i;
          y := - y_i;
        end if;

      when -1 =>
        -- Pre-step to collapse angle in [-pi/4 .. pi/4]
        -- Involves no scaling
        if angle(-1) /= angle(-2) or angle(-2) /= angle(-3) then
          if angle(-1) = '1' then
            angle := angle + to_ufixed(0.25, angle'left, angle'right);
            x := - y_i;
            y := x_i;
          else
            angle := angle - to_ufixed(0.25, angle'left, angle'right);
            x := y_i;
            y := - x_i;
          end if;
        end if;

      when others =>
        sincos_astep(angle, x, y, step);
    end case;
  end procedure;

  procedure sincos(angle_i : in ufixed;
                   x_o, y_o : out sfixed;
                   step_count : integer;
                   scale : real := 1.0)
  is
    variable angle : ufixed(-1 downto angle_i'right)
      := resize(angle_i, -1, angle_i'right);
    constant init_scale : real := sincos_scale(step_count);
    -- Only handle saturation once at the end, use one more bit for
    -- intermediate calculation
    variable x : sfixed(x_o'left+1 downto x_o'right-step_count/2);
    variable y : sfixed(y_o'left+1 downto y_o'right-step_count/2);
  begin
    -- Rather than multiplying by scaling factor, just insert it ahead of time.
    x := to_sfixed(init_scale * scale, x'left, x'right);
    y := to_sfixed(0.0, y'left, y'right);

    for i in -2 to step_count-1
    loop
      sincos_step(angle, x, y, i);
    end loop;

    x_o := resize_saturate(x, x_o'left, x_o'right);
    y_o := resize_saturate(-y, y_o'left, y_o'right);
  end procedure;

end package body cordic;
