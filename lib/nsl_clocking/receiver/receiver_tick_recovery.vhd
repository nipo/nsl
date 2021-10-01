library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_clocking;
use nsl_math.fixed.all;

entity receiver_tick_recovery is
  generic(
    period_max_c : natural range 4 to integer'high;
    run_length_max_c : natural := 3;
    tick_learn_c: natural := 64
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    reset_i : in std_ulogic := '0';
    tick_i : in std_ulogic;

    valid_o : out std_ulogic;
    tick_180_o : out std_ulogic
    );
end entity;

architecture beh of receiver_tick_recovery is

  type regs_t is
  record
    learn_to_go: integer range 0 to tick_learn_c - 1;
    learn_period, learn_counter: integer range 0 to (run_length_max_c + 1) * period_max_c;

    ref_period_valid: boolean;
    ref_period: integer range 0 to period_max_c;

    to_180: integer range 0 to period_max_c;
  end record;

  signal r, rin : regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.learn_counter <= 0;
      r.learn_period <= period_max_c;
      r.learn_to_go <= tick_learn_c - 1;
      r.ref_period_valid <= false;
    end if;
  end process;

  transition: process(r, tick_i) is
  begin
    rin <= r;

    if tick_i = '1' then
      rin.learn_counter <= 0;
      if r.learn_period >= r.learn_counter then
        rin.learn_period <= r.learn_counter;
      end if;

      if r.learn_to_go /= 0 then
        rin.learn_to_go <= r.learn_to_go - 1;
      else
        if r.learn_counter < period_max_c then
          rin.ref_period_valid <= true;
          rin.ref_period <= r.learn_period + 1;
        end if;

        rin.learn_period <= period_max_c;
        rin.learn_to_go <= tick_learn_c - 1;
        rin.learn_counter <= 0;
      end if;
    else
      if r.learn_counter < (period_max_c + 1) * run_length_max_c then
        rin.learn_counter <= r.learn_counter + 1;
      else
        rin.ref_period_valid <= false;
        rin.learn_period <= period_max_c;
        rin.learn_to_go <= tick_learn_c - 1;
        rin.learn_counter <= 0;
      end if;
    end if;

    if not r.ref_period_valid then
      rin.to_180 <= 0;
    else
      if tick_i = '1' then
        rin.to_180 <= r.ref_period / 2;
      elsif r.to_180 = 0 then
        rin.to_180 <= r.ref_period;
      else
        rin.to_180 <= r.to_180 - 1;
      end if;
    end if;
  end process;

  tick_180_o <= '1' when r.to_180 = 0 and r.ref_period_valid else '0';
  valid_o <= '1' when r.ref_period_valid else '0';
  
end architecture;
