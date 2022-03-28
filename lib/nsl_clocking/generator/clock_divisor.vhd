library ieee;
use ieee.std_logic_1164.all;

library nsl_math, work;
use nsl_math.fixed.all;

entity clock_divisor is
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    period_i : in ufixed;
    
    clock_o   : out std_ulogic
    );
end entity;

architecture beh of clock_divisor is

  subtype half_period_t is ufixed(period_i'left-1 downto period_i'right-1);

  type regs_t is
  record
    clock: std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal half_period_s : half_period_t;
  signal tick_s: std_ulogic;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.clock <= '0';
    end if;
  end process;

  transition: process(r, tick_s) is
  begin
    rin <= r;

    if tick_s = '1' then
      rin.clock <= not r.clock;
    end if;
  end process;

  clock_o <= r.clock;

  half_period_s <= period_i;
  
  ticker: work.generator.tick_generator
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      period_i => half_period_s,
      tick_o => tick_s
      );
  
end architecture;
