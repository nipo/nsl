library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

entity pps_ticker is
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    reference_i: in timestamp_t;

    tick_o: out std_ulogic
    );
end entity;

architecture beh of pps_ticker is

  type regs_t is
  record
    reference: timestamp_t;
    next_second: timestamp_second_t;
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
      r.reference <= timestamp_zero_c;
      r.next_second <= (others => '0');
      r.tick <= '0';
    end if;
  end process;

  transition: process(r, reference_i) is
  begin
    rin <= r;

    rin.reference <= reference_i;
    rin.tick <= '0';

    if r.reference.abs_change = '1' then
      rin.next_second <= r.reference.second + 1;
    elsif r.reference.second = r.next_second then
      rin.next_second <= r.next_second + 1;
      rin.tick <= '1';
    end if;
  end process;

  tick_o <= r.tick;

end architecture;
