library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.timing.all;

entity tick_tachometer is
  generic (
    clock_i_hz_c: real;
    update_rate_hz_c: real
    );
  port (
    reset_n_i     : in  std_ulogic;
    clock_i       : in  std_ulogic;

    tick_i : in std_ulogic;
    tick_per_period_o : out unsigned
    );
end entity;

architecture beh of tick_tachometer is

  subtype acc_t is unsigned(tick_per_period_o'length-1 downto 0);
  constant period_c: natural := to_cycles(1.0 / update_rate_hz_c, clock_i_hz_c);
  
  type regs_t is
  record
    div: natural range 0 to period_c - 1;
    acc, val: acc_t;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.div <= 0;
      r.acc <= (others => '0');
      r.val <= (others => '0');
    end if;
  end process;

  transition: process(r, tick_i) is
  begin
    rin <= r;

    if r.div /= 0 then
      rin.div <= r.div - 1;
      if tick_i = '1' then
        rin.acc <= r.acc + 1;
      end if;
    else
      rin.div <= period_c - 1;
      rin.val <= r.acc;
      
      if tick_i = '1' then
        rin.acc <= to_unsigned(1, rin.acc'length);
      else
        rin.acc <= to_unsigned(0, rin.acc'length);
      end if;
    end if;
  end process;

  tick_per_period_o <= r.val;
  
end architecture;
