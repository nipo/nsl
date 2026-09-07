library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_time, nsl_simulation, work;
use nsl_time.timestamp.all;
use nsl_time.discipline.all;

entity tb is
end tb;

-- Latency compensation on both ends of the pulse path, against a
-- synthetic time base that spends a second in a thousand cycles.
-- The pulse source is told the resynchronizer's own latency, so the
-- offset it reports must be the one at the pin edge; the ticker is
-- told a lead, so its tick must land that early before the boundary.
architecture arch of tb is

  constant clock_period_c : time := 10 ns;
  constant step_ns_c : natural := 1000000;
  constant second_ns_c : natural := 1000000000;
  -- async_input: sampler 2, debouncer 2, edge 1.
  constant pipeline_cycles_c : natural := 5;
  constant lead_cycles_c : natural := 3;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal time_s : timestamp_t;
  signal pps_s, offset_valid_s, adj_valid_s : std_ulogic;
  signal offset_s : timestamp_nanosecond_offset_t;
  signal tick_s, tick_lead_s : std_ulogic;

begin

  -- The time base itself: a second boundary every thousand cycles.
  base: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      time_s.abs_change <= '0';
      if time_s.nanosecond = to_unsigned(second_ns_c - step_ns_c,
                                         time_s.nanosecond'length) then
        time_s.nanosecond <= (others => '0');
        time_s.second <= time_s.second + 1;
      else
        time_s.nanosecond <= time_s.nanosecond + step_ns_c;
      end if;
    end if;

    if reset_n_s = '0' then
      time_s.second <= to_unsigned(10, time_s.second'length);
      time_s.nanosecond <= (others => '0');
      time_s.abs_change <= '0';
    end if;
  end process;

  source: nsl_time.discipline.discipline_pps_source
    generic map(
      align_threshold_ns_c => 400000000,
      input_delay_ns_c => pipeline_cycles_c * step_ns_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      pps_i => pps_s,
      timestamp_i => time_s,
      offset_o => offset_s,
      offset_valid_o => offset_valid_s,
      adj_o => open,
      adj_valid_o => adj_valid_s,
      tick_o => open
      );

  ticker: nsl_time.pps.pps_ticker
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      reference_i => time_s,
      tick_o => tick_s
      );

  ticker_lead: nsl_time.pps.pps_ticker
    generic map(
      lead_ns_c => lead_cycles_c * step_ns_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      reference_i => time_s,
      tick_o => tick_lead_s
      );

  -- Pulses raised at known places in the second.
  stim: process
    procedure pulse_at(ns : natural; expect : integer) is
      variable seen : boolean := false;
    begin
      wait until rising_edge(clock_s)
        and time_s.nanosecond = to_unsigned(ns, time_s.nanosecond'length);
      pps_s <= '1';
      for i in 1 to 20 loop
        wait until rising_edge(clock_s);
        if offset_valid_s = '1' then
          assert not seen report "offset reported twice" severity failure;
          seen := true;
          assert to_integer(offset_s) = expect
            report "pulse at " & integer'image(ns) & " ns: offset "
            & integer'image(to_integer(offset_s)) & ", expected "
            & integer'image(expect)
            severity failure;
        end if;
        assert adj_valid_s = '0' report "unexpected adjustment" severity failure;
      end loop;
      assert seen report "no offset for the pulse at " & integer'image(ns)
        severity failure;
      pps_s <= '0';
      for i in 1 to 20 loop
        wait until rising_edge(clock_s);
      end loop;
    end procedure;
  begin
    done_s(0) <= '0';
    pps_s <= '0';
    wait until reset_n_s = '1';
    for i in 1 to 10 loop
      wait until rising_edge(clock_s);
    end loop;

    -- The reported offset is the time base at the edge itself, the
    -- pipeline taken off, folded around the boundary.
    pulse_at(7 * step_ns_c, 7 * step_ns_c);
    pulse_at(0, 0);
    pulse_at(second_ns_c - 2 * step_ns_c, -2 * step_ns_c);
    pulse_at(second_ns_c - 5 * step_ns_c, -5 * step_ns_c);

    done_s(0) <= '1';
    wait;
  end process;

  -- The ticker answers two samples after its reference crosses the
  -- lead threshold, or the boundary for the plain one; each once a
  -- second.
  check_ticks: process
    variable plain, led : natural := 0;
  begin
    wait until reset_n_s = '1';
    -- The tickers resynchronize on the time base over the first cycles.
    for cycle in 1 to 5 loop
      wait until falling_edge(clock_s);
    end loop;
    for cycle in 1 to 4200 loop
      wait until falling_edge(clock_s);
      if tick_s = '1' then
        plain := plain + 1;
        assert time_s.nanosecond = to_unsigned(2 * step_ns_c, time_s.nanosecond'length)
          report "plain tick at " & integer'image(to_integer(time_s.nanosecond))
          severity failure;
      end if;
      if tick_lead_s = '1' then
        led := led + 1;
        assert time_s.nanosecond
          = to_unsigned(second_ns_c - (lead_cycles_c - 2) * step_ns_c,
                        time_s.nanosecond'length)
          report "led tick at " & integer'image(to_integer(time_s.nanosecond))
          severity failure;
      end if;
    end loop;
    assert plain = 4 report "plain ticks: " & integer'image(plain) severity failure;
    assert led = 4 report "led ticks: " & integer'image(led) severity failure;
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 3,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
