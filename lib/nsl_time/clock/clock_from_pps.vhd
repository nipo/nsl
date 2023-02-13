library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work, nsl_math, nsl_event, nsl_dsp, nsl_data;
use work.timestamp.all;
use nsl_math.fixed.all;
use nsl_math.arith.all;
use nsl_data.text.all;

entity clock_from_pps is
  generic(
    clock_nominal_hz_c: natural;
    clock_max_abs_ppm_c: real := 5.0
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    next_second_i: in timestamp_second_t;
    next_second_set_i: in std_ulogic;

    tick_i: in std_ulogic;

    timestamp_o : out timestamp_t
    );
end entity;

architecture beh of clock_from_pps is

  attribute mark_debug : string;

  constant period_ns_c : real := 1.0e9 / real(clock_nominal_hz_c);
  constant period_saturation_c: timestamp_nanosecond_t := to_unsigned(1e9 - 1 - integer(ceil(period_ns_c)), timestamp_nanosecond_t'length);

  constant period_increment_c: ufixed := to_ufixed_auto(period_ns_c, 24, fixed_length => true);

  constant max_extra_ns_f_c: real := 1.0e9 * 1.0e-6 * clock_max_abs_ppm_c;
  constant max_extra_ns_c: unsigned := to_unsigned_auto(integer(ceil(max_extra_ns_f_c)));

  constant max_extra_cycles_i_c: integer := integer(real(clock_nominal_hz_c) * 1.0e-6 * clock_max_abs_ppm_c);
  constant cycles_reload_c: signed := to_signed_auto(clock_nominal_hz_c-1);
  constant max_extra_cycles_c: unsigned := to_unsigned_auto(max_extra_cycles_i_c+1);
  
  type regs_t is
  record
    second: timestamp_second_t;
    second_abs_change: std_ulogic;

    next_second: timestamp_second_t;
    next_second_reset: std_ulogic;

    sub_nanosecond_acc: ufixed(-1 downto period_increment_c'right);
    nanosecond_inc: ufixed(period_increment_c'left+1 downto 0);

    period_nanosecond_flat: unsigned(period_increment_c'left+1 downto 0);
    period_nanosecond_p1: unsigned(period_increment_c'left+1 downto 0);
    period_nanosecond_m1: unsigned(period_increment_c'left+1 downto 0);
    nanosecond_acc: timestamp_nanosecond_t;
    cycle_left: signed(cycles_reload_c'range);

    add_cycles: boolean;
    cycle_to_smear: unsigned(max_extra_cycles_c'range);
    smear_updated: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
  signal smear_num_s, smear_num_lp_s : ufixed(max_extra_cycles_c'range);
  constant smear_denom_u_s : unsigned := to_unsigned_auto(integer(real(clock_nominal_hz_c) / period_ns_c));
  constant smear_denom_c : ufixed := to_ufixed_auto(real(clock_nominal_hz_c) / period_ns_c, smear_denom_u_s'length);
  signal smear_tick_s: std_ulogic;

  attribute mark_debug of smear_tick_s, smear_num_s, smear_num_lp_s: signal is "TRUE";

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.second <= (others => '0');
      r.second_abs_change <= '0';

      r.next_second <= (others => '0');
      r.next_second_reset <= '1';

      r.sub_nanosecond_acc <= (others => '0');
      r.nanosecond_inc <= (others => '0');

      r.period_nanosecond_flat <= (others => '0');
      r.period_nanosecond_p1 <= (others => '0');
      r.period_nanosecond_m1 <= (others => '0');
      r.cycle_left <= (others => '0');

      r.add_cycles <= false;
      r.cycle_to_smear <= (others => '0');

      r.smear_updated <= '0';
    end if;
  end process;

  transition: process(r, next_second_set_i, next_second_i, tick_i, smear_tick_s) is
    variable subns_sum: ufixed(period_increment_c'left+1 downto period_increment_c'right);
  begin
    rin <= r;

    rin.second_abs_change <= '0';
    rin.smear_updated <= '0';

    subns_sum := resize(period_increment_c, subns_sum'left, subns_sum'right)
                 + resize(r.sub_nanosecond_acc, subns_sum'left, subns_sum'right);
    rin.sub_nanosecond_acc <= subns_sum(rin.sub_nanosecond_acc'range);
    rin.nanosecond_inc <= subns_sum(rin.nanosecond_inc'range);

    rin.period_nanosecond_flat <= to_unsigned(r.nanosecond_inc);
    rin.period_nanosecond_p1 <= to_unsigned(r.nanosecond_inc) + 1;
    rin.period_nanosecond_m1 <= to_unsigned(r.nanosecond_inc) - 1;

    if r.nanosecond_acc < period_saturation_c then
      if smear_tick_s = '1' then
        if r.add_cycles then
          rin.nanosecond_acc <= r.nanosecond_acc + r.period_nanosecond_p1;
        else
          rin.nanosecond_acc <= r.nanosecond_acc + r.period_nanosecond_m1;
        end if;
      else
        rin.nanosecond_acc <= r.nanosecond_acc + r.period_nanosecond_flat;
      end if;
    else
      rin.nanosecond_acc <= to_unsigned(1e9 - 1, r.nanosecond_acc'length);
    end if;
    rin.cycle_left <= r.cycle_left - 1;


    if next_second_set_i = '1' and next_second_i /= r.next_second then
      rin.next_second <= next_second_i;
      rin.next_second_reset <= '1';
    end if;


    if tick_i = '1' then
      rin.next_second <= r.next_second + 1;
      rin.nanosecond_acc <= (others => '0');
      rin.cycle_left <= cycles_reload_c;
      if r.cycle_left >= 0 then
        rin.add_cycles <= true;
        rin.cycle_to_smear <= resize(unsigned(r.cycle_left), rin.cycle_to_smear'length);
      else
        rin.add_cycles <= false;
        rin.cycle_to_smear <= resize(unsigned(not r.cycle_left), rin.cycle_to_smear'length);
      end if;
      rin.second <= r.next_second;
      rin.second_abs_change <= r.next_second_reset;
      rin.next_second_reset <= '0';
      rin.smear_updated <= '1';
    end if;
  end process;

  smear_num_s <= ufixed(r.cycle_to_smear);

  lp: nsl_dsp.rc.rc_ufixed
    generic map(
      tau_c => 7
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      valid_i => r.smear_updated,
      in_i => smear_num_s,
      out_o => smear_num_lp_s
      );

  assert false
    report
      "clock from PPS, f=" & to_string(real(clock_nominal_hz_c) / 1.0e6) & " MHz"
    & " +- " & to_string(clock_max_abs_ppm_c) & " ppm"
    & " smears at most " & to_string(max_extra_cycles_c) & " cycles"
    & " through tick generator at " & to_string(smear_num_lp_s'length) & "bits / " & to_string(smear_denom_c)
    severity note;
  
  smearing_acc: nsl_event.tick.tick_generator_frac
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      freq_num_i => smear_num_lp_s,
      freq_denom_i => smear_denom_c,

      tick_o => smear_tick_s
      );

  timestamp_o.second <= r.second;
  timestamp_o.nanosecond <= r.nanosecond_acc;
  timestamp_o.abs_change <= r.second_abs_change;
  
end architecture;
