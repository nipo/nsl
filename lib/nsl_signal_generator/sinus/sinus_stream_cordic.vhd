library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math, nsl_data, nsl_memory;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;
use nsl_math.cordic.all;

entity sinus_stream_cordic is
  generic (
    scale_c : real := 1.0
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    angle_i : in ufixed;
    value_o : out sfixed
    );
end sinus_stream_cordic;

architecture beh of sinus_stream_cordic is

  --constant step_count : integer := 2 * nsl_math.arith.max(x_o'length, y_o'length);
  constant step_count : integer := value_o'length + angle_i'length;
  subtype a_t is ufixed(-1 downto angle_i'right);
  subtype xy_t is sfixed(value_o'left+1 downto -step_count/2);

  constant init_scale : real := sincos_scale(step_count);

  type a_vector is array(integer range <>) of a_t;
  type xy_vector is array(integer range <>) of xy_t;

  signal a: a_vector(-2 to step_count);
  signal x, y: xy_vector(-2 to step_count);

begin

  assert angle_i'left = -1
    report "angle_i'left must be -1"
    severity failure;
  
  reg: process(clock_i, reset_n_i) is
    variable a_n : a_t;
    variable x_n, y_n : xy_t;
  begin
    if rising_edge(clock_i) then
      a(-2) <= resize(angle_i, a(-2)'left, a(-2)'right);
      x(-2) <= to_sfixed(init_scale * scale_c, x(-2)'left, x(-2)'right);
      y(-2) <= to_sfixed(0.0, y(-2)'left, y(-2)'right);

      for i in -2 to step_count-1
      loop
        sincos_step(i, a_n, x_n, y_n, a(i), x(i), y(i));
        a(i+1) <= a_n;
        x(i+1) <= x_n;
        y(i+1) <= y_n;
      end loop;

      value_o <= resize_saturate(y(step_count), value_o'left, value_o'right);
    end if;

    if reset_n_i = '0' then
      a <= (others => (others => '0'));
      x <= (others => (others => '0'));
      y <= (others => (others => '0'));
    end if;
  end process;
  
end architecture;
