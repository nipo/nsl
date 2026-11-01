library ieee;
use ieee.std_logic_1164.all;

library nsl_transceiver;
use nsl_transceiver.prbs.all;

entity prbs_lock_detector is
  generic(
    lock_word_count_c : natural := 16;
    unlock_word_count_c : natural := 16
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    checking_i : in std_ulogic;
    restart_i : in std_ulogic;
    error_i : in std_ulogic;

    locked_o : out std_ulogic
    );
end entity;

architecture beh of prbs_lock_detector is

  -- Losing the pattern is counted by weight rather than by a run of
  -- errored words, because a run means different things at
  -- different widths: a checker that has not found the pattern
  -- mispredicts about half the bits it looks at, which errors
  -- nearly every word of thirty two bits but only half the words of
  -- one. An errored word therefore adds unlock_weight_c and a clean
  -- one takes away a single unit, so what the counter measures is
  -- errored words outnumbering clean ones. A line merely carrying
  -- the wrong pattern walks it up at any width, and a line carrying
  -- the right one with real bit errors never does, because there
  -- the clean words outnumber the others by orders of magnitude.
  constant unlock_weight_c : natural := 2;
  constant unlock_limit_c : natural := unlock_weight_c * unlock_word_count_c;

  type regs_t is
  record
    locked : std_ulogic;
    clean_count : natural range 0 to lock_word_count_c;
    dirty_count : natural range 0 to unlock_limit_c;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.locked <= '0';
      r.clean_count <= 0;
      r.dirty_count <= 0;
    end if;
  end process;

  transition: process(r, checking_i, restart_i, error_i) is
  begin
    rin <= r;

    if restart_i = '1' or checking_i = '0' then
      rin.locked <= '0';
      rin.clean_count <= 0;
      rin.dirty_count <= 0;
    elsif error_i = '1' then
      rin.clean_count <= 0;

      if r.dirty_count + unlock_weight_c < unlock_limit_c then
        rin.dirty_count <= r.dirty_count + unlock_weight_c;
      else
        rin.locked <= '0';
        rin.dirty_count <= 0;
      end if;
    else
      if r.dirty_count /= 0 then
        rin.dirty_count <= r.dirty_count - 1;
      end if;

      if r.clean_count /= lock_word_count_c then
        rin.clean_count <= r.clean_count + 1;
      else
        rin.locked <= '1';
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    locked_o <= r.locked;
  end process;

end architecture;
