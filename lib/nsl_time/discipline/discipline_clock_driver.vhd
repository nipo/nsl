library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use work.discipline.all;
use nsl_math.fixed.all;

entity discipline_clock_driver is
  generic(
    clock_i_hz_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    freq_offset_ppb_i : in frequency_ppb_t;

    sub_nanosecond_inc_o : out ufixed
    );
end entity;

architecture beh of discipline_clock_driver is

  constant inc_left_c : integer := sub_nanosecond_inc_o'left;
  constant inc_right_c : integer := sub_nanosecond_inc_o'right;
  -- Guard bits below the output, so that quantization of the
  -- correction happens once, on the output.
  constant inner_right_c : integer := inc_right_c - 4;

  constant nominal_ns_c : real := 1.0e9 / real(clock_i_hz_c);
  -- Nanoseconds per cycle per part per billion.
  constant ppb_ns_c : real := nominal_ns_c * 1.0e-9;

  -- to_sfixed() of a real goes through a VHDL integer, which caps the
  -- constant at 31 bits; the increment of a slow clock needs more.
  function to_sfixed_wide(value : real;
                          constant left, right : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
    variable acc : real;
  begin
    assert 0.0 <= value and value < 2.0 ** left
      report "Value is not representable"
      severity failure;

    ret := (others => '0');
    acc := value;
    for i in left-1 downto right loop
      if acc >= 2.0 ** i then
        ret(i) := '1';
        acc := acc - 2.0 ** i;
      end if;
    end loop;

    return ret;
  end function;

  subtype inner_t is sfixed(inc_left_c+1 downto inner_right_c);

  constant nominal_c : inner_t
    := to_sfixed_wide(nominal_ns_c, inner_t'left, inner_t'right);
  constant ppb_scale_left_c : integer := sfixed_left(ppb_ns_c);
  constant ppb_scale_c : sfixed(ppb_scale_left_c downto ppb_scale_left_c-25)
    := to_sfixed_wide(ppb_ns_c, ppb_scale_left_c, ppb_scale_left_c-25);
  constant nominal_inc_c : ufixed(inc_left_c downto inc_right_c)
    := to_ufixed_saturate(nominal_c, inc_left_c, inc_right_c);

  type regs_t is
  record
    inc : ufixed(inc_left_c downto inc_right_c);
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.inc <= nominal_inc_c;
    end if;
  end process;

  transition: process(r, freq_offset_ppb_i) is
    variable correction : inner_t;
  begin
    rin <= r;

    correction := mul(to_sfixed(freq_offset_ppb_i), ppb_scale_c,
                      inner_t'left, inner_t'right);
    rin.inc <= to_ufixed_saturate(add_saturate(nominal_c, correction),
                                  inc_left_c, inc_right_c);
  end process;

  moore: process(r) is
  begin
    sub_nanosecond_inc_o <= r.inc;
  end process;

end architecture;
