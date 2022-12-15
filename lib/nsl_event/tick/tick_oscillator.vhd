library ieee;
use ieee.std_logic_1164.all;

entity tick_oscillator is
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;
    osc_o : out std_ulogic
    );
end entity;

architecture beh of tick_oscillator is
  
  type regs_t is
  record
    osc: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.osc <= '0';
    end if;
  end process;

  transition: process(r, tick_i) is
  begin
    rin <= r;

    rin.osc <= r.osc xor tick_i;
  end process;

  osc_o <= r.osc;

end architecture;
