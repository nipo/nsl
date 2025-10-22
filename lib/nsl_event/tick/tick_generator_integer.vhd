library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tick_generator_integer is
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    period_m1_i : in unsigned;
    
    tick_o   : out std_ulogic
    );
end entity;

architecture beh of tick_generator_integer is

  subtype acc_t is unsigned(period_m1_i'range);

  type regs_t is
  record
    acc: acc_t;
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
    end if;
  end process;

  transition: process(r, period_m1_i) is
  begin
    rin <= r;

    if r.acc = 0 then
      rin.acc <= period_m1_i;
      rin.tick <= '1';
    else
      rin.acc <= to_01(r.acc - 1, '0');
      rin.tick <= '0';
    end if;
  end process;

  tick_o <= r.tick;
  
end architecture;
