library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver;
use nsl_transceiver.lane.all;
use nsl_transceiver.prbs.all;

entity prbs_checker is
  generic(
    -- Bits of line looked at per clock, matching the generator's.
    bit_count_c : natural;
    lock_word_count_c : natural := 16;
    unlock_word_count_c : natural := 16
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    mode_i : in prbs_mode_t;
    restart_i : in std_ulogic;

    -- Oldest bit first, as the generator hands them over.
    data_i : in std_ulogic_vector(0 to bit_count_c-1);
    valid_i : in std_ulogic;

    locked_o : out std_ulogic;
    error_o : out std_ulogic;
    error_bit_count_o : out integer range 0 to bit_count_c
    );
end entity;

architecture beh of prbs_checker is

  subtype window_t is std_ulogic_vector(0 to max_order_c + bit_count_c - 1);

  type regs_t is
  record
    history : history_t;
    locked : std_ulogic;
    -- Words in a row that agreed, or in a row that did not.
    clean_count : natural range 0 to lock_word_count_c;
    dirty_count : natural range 0 to unlock_word_count_c;
    error : std_ulogic;
    error_bit_count : natural range 0 to bit_count_c;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.history <= (others => '0');
      r.locked <= '0';
      r.clean_count <= 0;
      r.dirty_count <= 0;
      r.error <= '0';
      r.error_bit_count <= 0;
    end if;
  end process;

  transition: process(r, mode_i, restart_i, data_i, valid_i) is
    variable window_v : window_t;
    variable deep_v, shallow_v : natural;
    variable errors_v : natural range 0 to bit_count_c;
    variable predicted_v : std_ulogic;
  begin
    rin <= r;
    rin.error <= '0';
    rin.error_bit_count <= 0;

    deep_v := deep_tap(mode_i);
    shallow_v := shallow_tap(mode_i);

    if restart_i = '1' or mode_i = PRBS_NONE then
      rin.locked <= '0';
      rin.clean_count <= 0;
      rin.dirty_count <= 0;
    elsif valid_i = '1' then
      window_v := (others => '0');
      window_v(0 to max_order_c-1) := r.history;
      errors_v := 0;

      for i in max_order_c to max_order_c + bit_count_c - 1 loop
        predicted_v := window_v(i - deep_v) xor window_v(i - shallow_v);

        if predicted_v /= data_i(i - max_order_c) then
          errors_v := errors_v + 1;
        end if;

        -- Hunting takes the line's word for it, which is what makes
        -- the predictor converge on the phase the line is at.
        -- Locked, it takes its own, so a wrong bit on the line is
        -- not read back out of the history at each depth the
        -- polynomial taps and counted again.
        if r.locked = '1' then
          window_v(i) := predicted_v;
        else
          window_v(i) := data_i(i - max_order_c);
        end if;
      end loop;

      rin.history <= window_v(bit_count_c to bit_count_c + max_order_c - 1);
      rin.error_bit_count <= errors_v;

      if errors_v = 0 then
        rin.dirty_count <= 0;
        if r.clean_count /= lock_word_count_c then
          rin.clean_count <= r.clean_count + 1;
        else
          rin.locked <= '1';
        end if;
      else
        rin.error <= '1';
        rin.clean_count <= 0;
        if r.dirty_count /= unlock_word_count_c then
          rin.dirty_count <= r.dirty_count + 1;
        else
          rin.locked <= '0';
          rin.dirty_count <= 0;
        end if;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    locked_o <= r.locked;
    error_o <= r.error;
    error_bit_count_o <= r.error_bit_count;
  end process;

end architecture;
