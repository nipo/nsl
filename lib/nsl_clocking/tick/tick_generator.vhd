library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

entity tick_generator is
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    period_i : in ufixed;
    
    tick_o   : out std_ulogic
    );
end entity;

architecture beh of tick_generator is

  constant msb: integer := nsl_math.arith.max(period_i'left, 0) + 1;
  constant lsb: integer := nsl_math.arith.min(period_i'right, 0);
  subtype acc_t is ufixed(msb downto lsb);
  constant unit: acc_t := to_ufixed(1.0, msb, lsb);

  type regs_t is
  record
    period, nperiod_p1, acc: acc_t;
    tick: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.acc <= (others => '0');
      r.period <= (others => '0');
      r.nperiod_p1 <= (others => '0');
    end if;
  end process;

  transition: process(r, period_i) is
  begin
    rin <= r;

    rin.period <= resize(period_i, rin.period'left, rin.period'right);
    rin.nperiod_p1 <= unit - r.period;

    if r.acc >= r.period then
      rin.acc <= r.acc + r.nperiod_p1;
      rin.tick <= '1';
    else
      rin.acc <= r.acc + unit;
      rin.tick <= '0';
    end if;
  end process;

  tick_o <= r.tick;
  
end architecture;
