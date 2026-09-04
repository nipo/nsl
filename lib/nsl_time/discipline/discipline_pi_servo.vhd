library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;
use work.discipline.all;

entity discipline_pi_servo is
  generic(
    kp_l2_c : natural := 2;
    ki_l2_c : natural := 6;
    freq_clamp_ppb_c : natural := 100000
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    clear_i : in std_ulogic := '0';

    offset_i : in timestamp_nanosecond_offset_t;
    offset_valid_i : in std_ulogic;

    freq_offset_ppb_o : out frequency_ppb_t
    );
end entity;

architecture beh of discipline_pi_servo is

  -- Holds a shift-by-zero offset, its negation, and the sum of a
  -- proportional term with a clamped integrator.
  constant acc_left_c : integer := offset_i'length + 1;
  subtype acc_t is signed(acc_left_c downto 0);

  constant clamp_c : acc_t := to_signed(freq_clamp_ppb_c, acc_t'length);

  function clamped(value : acc_t) return acc_t
  is
  begin
    if value > clamp_c then
      return clamp_c;
    elsif value < -clamp_c then
      return -clamp_c;
    end if;
    return value;
  end function;

  type regs_t is
  record
    integrator : acc_t;
    proportional : acc_t;
    sum_pending : std_ulogic;
    freq_offset : frequency_ppb_t;
  end record;

  signal r, rin : regs_t;

begin

  assert freq_clamp_ppb_c < 2 ** (frequency_ppb_t'length - 1)
    report "Frequency clamp does not fit in output word"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.integrator <= (others => '0');
      r.proportional <= (others => '0');
      r.sum_pending <= '0';
      r.freq_offset <= (others => '0');
    end if;
  end process;

  transition: process(r, clear_i, offset_i, offset_valid_i) is
    variable offset : acc_t;
  begin
    rin <= r;

    offset := resize(offset_i, acc_t'length);

    rin.sum_pending <= offset_valid_i;

    if offset_valid_i = '1' then
      rin.proportional <= -shift_right(offset, kp_l2_c);
      rin.integrator <= clamped(r.integrator - shift_right(offset, ki_l2_c));
    end if;

    if r.sum_pending = '1' then
      rin.freq_offset <= resize(clamped(r.proportional + r.integrator),
                                frequency_ppb_t'length);
    end if;

    if clear_i = '1' then
      rin.integrator <= (others => '0');
      rin.proportional <= (others => '0');
      rin.sum_pending <= '0';
      rin.freq_offset <= (others => '0');
    end if;
  end process;

  moore: process(r) is
  begin
    freq_offset_ppb_o <= r.freq_offset;
  end process;

end architecture;
