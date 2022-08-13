library ieee;
use ieee.std_logic_1164.all;

library work;

entity tick_extractor_clock is
  generic(
    edge_c: std_ulogic := '1';
    divisor_c: positive := 1
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    signal_i : in std_ulogic;
    tick_o : out std_ulogic
    );
end entity;

architecture beh of tick_extractor_clock is

  type regs_t is
  record
    v: std_ulogic_vector(0 to 1);
  end record;

  signal r, rin: regs_t;
  signal tick_s: std_ulogic;

begin

  regs: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, signal_i) is
  begin
    rin <= r;

    rin.v <= signal_i & r.v(0);
  end process;

  tick_s <= '1' when (r.v(0) = edge_c and r.v(1) = not edge_c) else '0';

  div: work.tick.tick_divisor
    generic map(
      divisor_c => divisor_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      tick_i => tick_s,
      tick_o => tick_o
      );
  
end architecture;
