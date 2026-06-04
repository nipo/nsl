library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

entity tick_180_generator is
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    period_i : in ufixed;

    tick_i : in std_ulogic;
    tick_o : out std_ulogic
    );
end entity;

architecture beh of tick_180_generator is
  
  type regs_t is
  record
    counter: ufixed(period_i'range);
    period_m1: ufixed(period_i'range);
    period_d2_m1: ufixed(period_i'left-1 downto period_i'right);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.counter <= (others => '0');
      r.period_m1 <= (others => '0');
      r.period_d2_m1 <= (others => '0');
    end if;
  end process;

  transition: process(r, tick_i, period_i) is
    variable half_period: ufixed(period_i'left-1 downto period_i'right);
  begin
    rin <= r;

    half_period := resize(shr(period_i, 1), half_period'left, half_period'right)
                   - to_ufixed(1.0, half_period'left, half_period'right);

    if tick_i = '1' then
      rin.period_m1 <= period_i - to_ufixed(1.0, period_i'left, period_i'right);
      rin.period_d2_m1 <= half_period;
      rin.counter <= resize(half_period, r.counter'left, r.counter'right);
    elsif to_unsigned(resize(r.counter, r.counter'left, 0)) = 0 then
      rin.counter <= r.counter + r.period_m1;
    else
      rin.counter <= r.counter - to_ufixed(1.0, r.counter'left, r.counter'right);
    end if;
  end process;

  tick_o <= '1' when to_unsigned(resize(r.counter, r.counter'left, 0)) = 0 else '0';

end architecture;
