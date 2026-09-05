library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_math, work;
use work.discipline.all;
use nsl_math.fixed.all;

entity discipline_clock_driver is
  generic(
    clock_hz_c : natural
    );
  port(
    reset_n_i : in std_ulogic;

    clock_i : in std_ulogic;
    freq_offset_ppb_i : in frequency_ppb_t;

    rtc_clock_i : in std_ulogic;
    sub_nanosecond_inc_o : out ufixed
    );
end entity;

architecture beh of discipline_clock_driver is

  constant inc_left_c : integer := sub_nanosecond_inc_o'left;
  constant inc_right_c : integer := sub_nanosecond_inc_o'right;
  -- Guard bits below the output, so that quantization of the
  -- correction happens once, on the output.
  constant inner_right_c : integer := inc_right_c - 4;

  constant nominal_ns_c : real := 1.0e9 / real(clock_hz_c);
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

  -- What crosses is the correction, not the increment it maps to: the
  -- crossing is then 24 bits whatever resolution the time base asks
  -- from sub_nanosecond_inc_o, and the arithmetic lands in the domain
  -- that consumes it.  The input register of the slice is the sampling
  -- point in the command domain, so freq_offset_ppb_i is wired to it
  -- directly.
  signal cross_data_s, crossed_data_s
    : std_ulogic_vector(frequency_ppb_t'length-1 downto 0);
  signal crossed_valid_s : std_ulogic;

begin

  cross_data_s <= std_ulogic_vector(freq_offset_ppb_i);

  crossing: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => frequency_ppb_t'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      clock_i(1) => rtc_clock_i,

      in_data_i => cross_data_s,
      in_valid_i => '1',
      in_ready_o => open,

      out_data_o => crossed_data_s,
      out_ready_i => '1',
      out_valid_o => crossed_valid_s
      );

  rtc_side: block is
    type regs_t is
    record
      inc : ufixed(inc_left_c downto inc_right_c);
    end record;

    signal r, rin : regs_t;
  begin
    regs: process(rtc_clock_i, reset_n_i) is
    begin
      if rising_edge(rtc_clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.inc <= nominal_inc_c;
      end if;
    end process;

    -- An increment that is a mixture of two corrections is a wrong
    -- frequency, and one cycle of it is a time error the time base
    -- never gives back.  The register therefore only ever loads from a
    -- word the crossing has committed.
    transition: process(r, crossed_data_s, crossed_valid_s) is
      variable correction : inner_t;
    begin
      rin <= r;

      correction := mul(to_sfixed(signed(crossed_data_s)), ppb_scale_c,
                        inner_t'left, inner_t'right);
      if crossed_valid_s = '1' then
        rin.inc <= to_ufixed_saturate(add_saturate(nominal_c, correction),
                                      inc_left_c, inc_right_c);
      end if;
    end process;

    moore: process(r) is
    begin
      sub_nanosecond_inc_o <= r.inc;
    end process;
  end block;

end architecture;
