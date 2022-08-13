library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math;
use nsl_math.fixed.all;
use nsl_math.cordic.all;

entity rect_cordic_scaled is
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    scale_i : in sfixed;

    angle_i : in ufixed;
    ready_o : out std_ulogic;
    valid_i : in std_ulogic;

    y_o : out sfixed;
    x_o : out sfixed;
    valid_o : out std_ulogic;
    ready_i : in std_ulogic
    );
end rect_cordic_scaled;

architecture beh of rect_cordic_scaled is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_STEP_M2,
    ST_STEP_M1,
    ST_STEPS,
    ST_SAT,
    ST_RESP
    );

  constant step_count : integer := nsl_math.arith.max(x_o'left, y_o'left) + nsl_math.arith.max(-x_o'right, -y_o'right);
  constant prec_addend : integer := nsl_math.arith.log2(step_count+1);
  
  subtype rot_t is ufixed(-1 downto needed_angle_lsb(step_count));
  type rot_vector is array(integer range <>) of rot_t;

  function make_step_table(steps: integer) return rot_vector
  is
    variable ret: rot_vector(0 to steps-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_ufixed(sincos_angle_delta(i), ret(i)'left, ret(i)'right);
    end loop;
    return ret;
  end function;

  constant step_delta : rot_vector(0 to step_count-1) := make_step_table(step_count);

  type regs_t is
  record
    state : state_t;
    step : integer range 0 to step_count-1;
    angle_error : rot_t;
    x : sfixed(x_o'left+1 downto x_o'right-prec_addend);
    y : sfixed(y_o'left+1 downto y_o'right-prec_addend);
  end record;
  
  signal r, rin: regs_t;

begin

  assert scale_i'left = x_o'left + 1
    report "Bad scale_i left bound"
    severity failure;

  assert scale_i'right = x_o'right - prec_addend
    report "Bad scale_i right bound"
    severity failure;
  
  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, valid_i, ready_i, angle_i, scale_i)
    variable dy : sfixed(r.x'range);
    variable dx : sfixed(r.y'range);
    variable xo : sfixed(r.x'range);
    variable yo : sfixed(r.y'range);
    variable ao : ufixed(r.angle_error'range);
    variable rot : rot_t;
  begin
    rin <= r;

    rot := step_delta(r.step);
    dy := shr(r.y, r.step);
    dx := shr(r.x, r.step);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          rin.angle_error <= resize(angle_i, rin.angle_error'left, rin.angle_error'right);
          rin.state <= ST_STEP_M2;
          rin.x <= scale_i;
          rin.y <= to_sfixed(0.0, rin.y'left, rin.y'right);
        end if;

      when ST_STEP_M2 =>
        sincos_half_collapse(ao, xo, yo, r.angle_error, r.x, r.y);
        rin.angle_error <= ao;
        rin.x <= xo;
        rin.y <= yo;
        rin.state <= ST_STEP_M1;

      when ST_STEP_M1 =>
        sincos_fourth_collapse(ao, xo, yo, r.angle_error, r.x, r.y);
        rin.angle_error <= ao;
        rin.x <= xo;
        rin.y <= yo;
        rin.state <= ST_STEPS;
        rin.step <= 0;

      when ST_STEPS =>
        sincos_astep(r.step, rot, ao, xo, yo, r.angle_error, r.x, r.y);
        rin.angle_error <= ao;
        rin.x <= xo;
        rin.y <= yo;
        if r.step = step_count - 1 then
          rin.state <= ST_SAT;
        else
          rin.step <= r.step + 1;
        end if;

      when ST_SAT =>
        rin.x(x_o'range) <= resize_saturate(r.x, x_o'left, x_o'right);
        rin.y(y_o'range) <= resize_saturate(r.y, y_o'left, y_o'right);
        rin.state <= ST_RESP;

      when ST_RESP =>
        if ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    valid_o <= '0';
    ready_o <= '0';

    case r.state is
      when ST_IDLE =>
        ready_o <= '1';
      when ST_RESP =>
        valid_o <= '1';
      when others =>
        null;
    end case;
  end process;

  y_o <= r.y(y_o'range);
  x_o <= r.x(x_o'range);

end architecture;
