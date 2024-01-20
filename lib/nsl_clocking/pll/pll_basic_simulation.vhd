library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

-- For simulation purposes, do not actually model a phase comparator, but
-- simply do a frequency measurement and multiplication.

-- Take input clock stability and presence into account nonetheless.

entity pll_basic is
  generic(
    input_hz_c  : natural;
    output_hz_c : natural;
    hw_variant_c : string := ""
    );
  port(
    clock_i    : in  std_ulogic;
    clock_o    : out std_ulogic;

    reset_n_i  : in  std_ulogic;
    locked_o   : out std_ulogic
    );
end entity;

architecture sim of pll_basic is

  constant clock_ratio_c : real := real(input_hz_c) / real(output_hz_c);
  constant clock_i_period_c : real := 1.0 / real(input_hz_c);
  constant allowable_jitter_c : real := 0.03;
  constant allowable_error_c : real := 0.1;
  constant input_lowpass_factor_c : real := 256.0;
  constant stable_cycle_count_c : integer := 256;
  
  signal clock_i_in_range, clock_i_locked, clock_i_running, clock_i_stable : boolean;
  signal clock_i_stable_to_go : integer range 0 to stable_cycle_count_c-1;
  signal clock_i_period_lp, clock_o_period : real;
  signal last_clock_i_edge : time := 0 ps;

  function to_time(seconds: real) return time
  is
  begin
    return 1 ps * integer(seconds * 1.0e12);
  end function;

  function to_real(t: time) return real
  is
  begin
    return real(t / 1 ps) / 1.0e12;
  end function;

  signal period_s : real;
  
begin

  clock_i_measure : process(clock_i, reset_n_i) is
    variable period_time : time;
  begin
    if rising_edge(clock_i) then
      if last_clock_i_edge /= 0 ps then
        period_time := now - last_clock_i_edge;
        period_s <= to_real(period_time);
        clock_i_period_lp <= clock_i_period_lp
                             + (period_s - clock_i_period_lp) / input_lowpass_factor_c;
      end if;

      if abs(period_s - clock_i_period_lp)
        > clock_i_period_lp * allowable_jitter_c
        or not clock_i_in_range
        or not clock_i_running then
        clock_i_stable_to_go <= stable_cycle_count_c - 1;
      elsif clock_i_stable_to_go /= 0 then
        clock_i_stable_to_go <= clock_i_stable_to_go - 1;
      end if;

      last_clock_i_edge <= now;
    end if;
    if reset_n_i = '0' then
      last_clock_i_edge <= 0 ps;

      clock_i_period_lp <= clock_i_period_c;
      clock_i_stable_to_go <= stable_cycle_count_c - 1;
    end if;
  end process clock_i_measure;

  timeouter: process
    variable checkpoint, deadline, interval : time := 0 ps;
  begin
    while true
    loop
      clock_i_running <= false;
      wait until last_clock_i_edge'event;

      while clock_i_in_range
      loop
        checkpoint := last_clock_i_edge;
        interval := to_time(clock_i_period_lp * (1.0 + allowable_jitter_c));
        deadline := checkpoint + interval;

        if deadline <= now then
          exit;
        end if;

        clock_i_running <= true;

        wait for deadline - now;
      end loop;
    end loop;
  end process;

  clock_i_stable <= clock_i_stable_to_go = 0;
  clock_i_in_range <= abs(clock_i_period_c - clock_i_period_lp)
                      < clock_i_period_c * allowable_error_c;
  clock_i_locked <= clock_i_stable and clock_i_running and clock_i_in_range;

  period_updater: process (clock_i_period_lp) is
  begin
    if clock_i_period_lp > 0.0 and clock_i_period_lp < 1.0e-3 then
      clock_o_period <= clock_i_period_lp * clock_ratio_c;
    else
      clock_o_period <= 1.0e-3;
    end if;
  end process;
  
  clock_o_gen: process
    variable half_period : time := 0 ps;
    variable startup : integer;
  begin
    clock_o <= '0';
    locked_o <= '0';

    wait until clock_i_locked;
    startup := 10;
    while clock_i_locked
    loop
      half_period := to_time(clock_o_period / 2.0);
      clock_o <= '1';
      wait for half_period;
      clock_o <= '0';
      wait for half_period;

      if startup /= 0 then
        startup := startup - 1;
      else
        locked_o <= '1';
      end if;
    end loop;
  end process;  
  
end architecture;
