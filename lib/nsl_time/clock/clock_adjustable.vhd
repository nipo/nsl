library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use nsl_math.fixed.all;
use work.timestamp.all;

entity clock_adjustable is
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    sub_nanosecond_inc_i: in ufixed;

    nanosecond_adj_i: in timestamp_nanosecond_offset_t := (others => '0');
    nanosecond_adj_set_i: in std_ulogic := '0';

    timestamp_i: in timestamp_t;
    timestamp_set_i: in std_ulogic := '0';

    timestamp_o: out timestamp_t
    );
end entity;

architecture beh of clock_adjustable is

  constant subns_increment_left_c: integer := nsl_math.arith.max(0, sub_nanosecond_inc_i'left);
  constant subns_increment_right_c: integer := nsl_math.arith.min(-1, sub_nanosecond_inc_i'right);

  type regs_t is
  record
    subns_increment: ufixed(subns_increment_left_c downto subns_increment_right_c);
    subns_accumulator: ufixed(-1 downto subns_increment_right_c);

    ns_increment_internal: ufixed(subns_increment_left_c+1 downto 0);
    ns_increment_external: sfixed(nanosecond_adj_i'length-1 downto 0);
    ns_increment: sfixed(nanosecond_adj_i'length downto 0);

    ns_increment_th_under, ns_increment_th_over: sfixed(31 downto 0);
    ns_increment_value, ns_increment_plus_sec_value, ns_increment_minus_sec_value: sfixed(31 downto 0);

    ns_accumulator: sfixed(31 downto 0);

    s_increment: sfixed(1 downto 0);
    s_accumulator: ufixed(31 downto 0);
    ns_accumulator_resync: sfixed(31 downto 0);
    abs_change: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.abs_change <= '0';
      r.subns_increment <= (others => '0');
      r.subns_accumulator <= (others => '0');
      r.ns_increment_internal <= (others => '0');
      r.ns_increment_external <= (others => '0');
      r.ns_increment <= (others => '0');
      r.ns_increment_th_under <= (others => '0');
      r.ns_increment_th_over <= (others => '0');
      r.ns_accumulator <= (others => '0');
      r.ns_increment_value <= (others => '0');
      r.ns_increment_plus_sec_value <= (others => '0');
      r.ns_increment_minus_sec_value <= (others => '0');
      r.s_increment <= (others => '0');
      r.s_accumulator <= (others => '0');
      r.ns_accumulator_resync <= (others => '0');
    end if;
  end process;

  transition: process(r,
                      sub_nanosecond_inc_i,
                      nanosecond_adj_i,
                      nanosecond_adj_set_i,
                      timestamp_i,
                      timestamp_set_i) is
    variable subns_sum: ufixed(r.ns_increment_internal'left downto r.subns_accumulator'right);
    variable ns_acc_override_u: ufixed(timestamp_i.nanosecond'range);
    variable ns_acc_override_s: sfixed(timestamp_i.nanosecond'left+1 downto timestamp_i.nanosecond'right);
    variable s_acc_override: ufixed(timestamp_i.second'range);
  begin
    rin <= r;

    rin.abs_change <= '0';

    -- Register sub-nanosecond increment
    rin.subns_increment <= resize(sub_nanosecond_inc_i, rin.subns_increment'left, rin.subns_increment'right);

    -- Accumulate sub-nanoseconds
    subns_sum := resize(r.subns_increment, subns_sum'left, subns_sum'right)
                 + resize(r.subns_accumulator, subns_sum'left, subns_sum'right);

    -- Extract integer / fractional parts
    rin.subns_accumulator <= subns_sum(rin.subns_accumulator'range);
    rin.ns_increment_internal <= subns_sum(rin.ns_increment_internal'range);

    -- By default, there is no adjustment
    rin.ns_increment_external <= (others => '0');
    -- Override if any
    if nanosecond_adj_set_i = '1' then
      rin.ns_increment_external <= sfixed(nanosecond_adj_i);
    end if;

    -- Now we have next global nanosecond increment (external may be negative)
    rin.ns_increment <= add_extend(r.ns_increment_external,
                                   resize(to_sfixed(r.ns_increment_internal), rin.ns_increment_external'left, rin.ns_increment_external'right));

    -- Precalculate offsets
    rin.ns_increment_th_over <= to_sfixed(1.0e9, rin.ns_increment_th_over'left, rin.ns_increment_th_over'right)
                                - resize(r.ns_increment, rin.ns_increment_th_over'left, rin.ns_increment_th_over'right);
    rin.ns_increment_th_under <= - resize(r.ns_increment, rin.ns_increment_th_under'left, rin.ns_increment_th_under'right);
    rin.ns_increment_value <= resize(r.ns_increment, rin.ns_increment_th_under'left, rin.ns_increment_th_under'right);
    rin.ns_increment_plus_sec_value <= resize(r.ns_increment, rin.ns_increment_plus_sec_value'left, rin.ns_increment_plus_sec_value'right)
                                       + to_sfixed(1.0e9, rin.ns_increment_plus_sec_value'left, rin.ns_increment_plus_sec_value'right);
    rin.ns_increment_minus_sec_value <= resize(r.ns_increment, rin.ns_increment_minus_sec_value'left, rin.ns_increment_minus_sec_value'right)
                                        - to_sfixed(1.0e9, rin.ns_increment_minus_sec_value'left, rin.ns_increment_minus_sec_value'right);

    -- Accumulate nanoseconds with overflow
    -- Accumulator is so low we will decrement the second accumulator.
    if r.ns_accumulator < r.ns_increment_th_under then
      rin.ns_accumulator <= r.ns_accumulator + r.ns_increment_plus_sec_value;
      rin.s_increment <= "11"; -- -1
    elsif r.ns_accumulator < r.ns_increment_th_over then
      rin.ns_accumulator <= r.ns_accumulator + r.ns_increment_value;
      rin.s_increment <= "00"; -- 0
    else
      rin.ns_accumulator <= r.ns_accumulator + r.ns_increment_minus_sec_value;
      rin.s_increment <= "01"; -- +1
    end if;

    rin.ns_accumulator_resync <= r.ns_accumulator;
    rin.s_accumulator <= r.s_accumulator + ufixed(resize(r.s_increment, r.s_accumulator'left, r.s_accumulator'right));

    s_acc_override := ufixed(timestamp_i.second);
    ns_acc_override_u := ufixed(timestamp_i.nanosecond);
    ns_acc_override_s := to_sfixed(ns_acc_override_u);
    
    if timestamp_set_i = '1' then
      rin.ns_accumulator <= resize(ns_acc_override_s, rin.ns_accumulator'left, rin.ns_accumulator'right);
      rin.ns_accumulator_resync <= resize(ns_acc_override_s, rin.ns_accumulator_resync'left, rin.ns_accumulator_resync'right);
      rin.s_accumulator <= s_acc_override;
      rin.abs_change <= '1';
    end if;
  end process;

  timestamp_o.second <= to_unsigned(r.s_accumulator);
  timestamp_o.nanosecond <= unsigned(to_suv(r.ns_accumulator_resync(timestamp_o.nanosecond'range)));
  timestamp_o.abs_change <= r.abs_change;

end architecture;
