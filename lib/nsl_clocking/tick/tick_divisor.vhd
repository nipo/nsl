library ieee;
use ieee.std_logic_1164.all;

entity tick_divisor is
  generic(
    divisor_c: positive
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;
    tick_o : out std_ulogic
    );
end entity;

architecture beh of tick_divisor is

  constant reload_c: natural := natural(divisor_c) - 1;
  
  type regs_t is
  record
    div: natural range 0 to reload_c;
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
    end if;
  end process;

  transition: process(r, tick_i) is
  begin
    rin <= r;

    if tick_i = '1' then
      if r.div = 0 then
        rin.div <= reload_c;
      else
        rin.div <= r.div - 1;
      end if;
    end if;
  end process;

  tick_o <= tick_i when r.div = 0 else '0';

end architecture;
