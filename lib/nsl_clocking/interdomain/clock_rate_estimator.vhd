library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math;
--library nsl_data;
--use nsl_data.text.all;

entity clock_rate_estimator is
  generic(
    clock_hz_c : real;
    rate_choice_c : nsl_math.real_ext.real_vector
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    measured_clock_i: in std_ulogic;
    rate_index_o: out unsigned
    );
end entity;

architecture beh of clock_rate_estimator is

  function lowest_delta return real is
    variable g : real := 1.0e100;
  begin
    for i in rate_choice_c'range
    loop
      for j in rate_choice_c'range
      loop
        if i /= j then
          g := realmin(g, abs(rate_choice_c(i) - rate_choice_c(j)));
        end if;
      end loop;
    end loop;
    return g;
  end function;

  function min_index return integer is
    variable ret : integer := rate_choice_c'low;
    variable min_value : real := rate_choice_c(rate_choice_c'low);
  begin
    for i in rate_choice_c'low + 1 to rate_choice_c'high
    loop
      if rate_choice_c(i) < min_value then
        min_value := rate_choice_c(i);
        ret := i;
      end if;
    end loop;
    return ret;
  end function;

  constant min_index_c : integer := min_index;
  constant min_rate_c : real := realmin(nsl_math.real_ext.min(rate_choice_c),
                                        lowest_delta / 2.0);
  constant decision_cycles_c : integer := integer(ceil(realmax(1.0, clock_hz_c / min_rate_c)));
  constant actual_rate_c : real := clock_hz_c / real(decision_cycles_c);

  constant counter_max_c : integer := integer(realmax(1.0, ceil(nsl_math.real_ext.max(rate_choice_c) / actual_rate_c)));
  constant counter_max_l2_c : integer := nsl_math.arith.log2(counter_max_c);

  subtype counter_t is unsigned(counter_max_l2_c-1 downto 0);
  subtype index_t is unsigned(rate_index_o'length-1 downto 0);
  type counter_lut_t is array(integer range <>) of index_t;
  
  
  function lut_build return counter_lut_t is
    variable ret: counter_lut_t(0 to (2**counter_max_l2_c)-1);
    variable actual_freq : real;
    variable chosen : integer;
    variable smallest_diff, diff : real;
  begin
    ret := (others => (others => '1'));

    report "w:" & integer'image(counter_max_l2_c)
      & ", " & "decision_cycles_c:" & integer'image(decision_cycles_c);

    for i in ret'range
    loop
      actual_freq := real(i) * actual_rate_c;
      chosen := min_index_c - rate_choice_c'low;
      smallest_diff := 1.0e100;
      for j in rate_choice_c'range
      loop
        if i = 0 then
          diff := 1.0e100;
        elsif actual_freq < rate_choice_c(j) then
          diff := rate_choice_c(j) / actual_freq;
        else
          diff := actual_freq / rate_choice_c(j);
        end if;

        if diff < smallest_diff then
          chosen := j - rate_choice_c'low;
          smallest_diff := diff;
        end if;
      end loop;
--      report "i:" & integer'image(i)
--        & ", " & "rate:" & real'image(actual_freq)
--        & ", " &  "clo:" & integer'image(chosen)
--        & ", " &  "diff:" & real'image(smallest_diff)
--        ;
      ret(i) := to_unsigned(chosen, index_t'length);
    end loop;
    return ret;
  end function;

  constant rate_lut_c : counter_lut_t := lut_build;

  signal counter_s, counter_resync_s : counter_t := (others => '0');

  type regs_t is
  record
    cycles_to_go : integer range 0 to decision_cycles_c-1;
    last_counter : counter_t;
    counter_diff : counter_t;
    rate_index : index_t;
  end record;

  signal r, rin : regs_t;

begin

  free_running: process(measured_clock_i) is
  begin
    if rising_edge(measured_clock_i) then
      counter_s <= counter_s + 1;
    end if;
  end process;

  cross_domain: work.interdomain.interdomain_counter
    generic map(
      cycle_count_c => 2,
      data_width_c => counter_s'length,
      decode_stage_count_c => (counter_s'length + 3) / 4
      )
    port map(
      clock_in_i => measured_clock_i,
      clock_out_i => clock_i,
      data_i => counter_s,
      data_o => counter_resync_s
      );

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.last_counter <= (others => '0');
      r.cycles_to_go <= 0;
    end if;
  end process;

  transition: process(r, counter_resync_s) is
  begin
    rin <= r;

    if r.cycles_to_go /= 0 then
      rin.cycles_to_go <= r.cycles_to_go - 1;
    else
      rin.cycles_to_go <= decision_cycles_c - 1;
      rin.last_counter <= counter_resync_s;
      rin.counter_diff <= counter_resync_s - r.last_counter;
    end if;

    rin.rate_index <= rate_lut_c(to_integer(r.counter_diff));
  end process;

  rate_index_o <= r.rate_index;

end architecture;

