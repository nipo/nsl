library ieee;
use ieee.std_logic_1164.all;

library nsl_math;
use nsl_math.timing.all;

entity tick_pulse is
  generic(
    clock_hz_c : integer;
    assert_sec_c : real
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;
    pulse_o : out std_ulogic
    );
end entity;

architecture beh of tick_pulse is

  constant assert_cycles_c : natural := to_cycles(assert_sec_c, clock_hz_c);
  
  type regs_t is
  record
    left: integer range 0 to assert_cycles_c;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.left <= 0;
    end if;
  end process;

  transition: process(r, tick_i) is
  begin
    rin <= r;

    if tick_i = '1' then
      rin.left <= assert_cycles_c;
    elsif r.left /= 0 then
      rin.left <= r.left - 1;
    end if;
  end process;

  pulse_o <= '0' when r.left = 0 else '1';

end architecture;
