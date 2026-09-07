library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_time, nsl_simulation, work;
use nsl_time.timestamp.all;
use nsl_time.discipline.all;

entity tb is
end tb;

-- The setter is fed labels and ticks directly, with the time base
-- placed by hand on either side of a second boundary, far from it,
-- or already carrying the right second.
architecture arch of tb is

  constant clock_period_c : time := 8 ns;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal enable_s, second_valid_s, tick_s, set_s : std_ulogic;
  signal second_s : unsigned(31 downto 0);
  signal timestamp_s, set_timestamp_s : timestamp_t;

begin

  dut: nsl_time.discipline.discipline_second_setter
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      enable_i => enable_s,
      second_i => second_s,
      second_valid_i => second_valid_s,
      tick_i => tick_s,
      timestamp_i => timestamp_s,
      timestamp_o => set_timestamp_s,
      timestamp_set_o => set_s
      );

  stim: process
    procedure cycle is
    begin
      wait until rising_edge(clock_s);
    end procedure;

    procedure announce(sec : natural) is
    begin
      second_s <= to_unsigned(sec, second_s'length);
      second_valid_s <= '1';
      cycle;
      second_valid_s <= '0';
      cycle;
    end procedure;

    -- Ticks with the time base reading (sec, ns) and checks the
    -- setter's verdict on the following falling edge.
    procedure tick(name : string; sec, ns : natural;
                   set : boolean; set_sec : natural := 0) is
    begin
      timestamp_s.second <= to_unsigned(sec, timestamp_s.second'length);
      timestamp_s.nanosecond <= to_unsigned(ns, timestamp_s.nanosecond'length);
      timestamp_s.abs_change <= '0';
      cycle;
      tick_s <= '1';
      cycle;
      tick_s <= '0';
      wait until falling_edge(clock_s);
      assert (set_s = '1') = set
        report name & ": set_o is " & std_ulogic'image(set_s)
        severity failure;
      if set then
        assert set_timestamp_s.second = to_unsigned(set_sec, 32)
          report name & ": second set to "
          & integer'image(to_integer(set_timestamp_s.second))
          & ", expected " & integer'image(set_sec)
          severity failure;
        assert set_timestamp_s.nanosecond
          = to_unsigned(ns, timestamp_s.nanosecond'length)
          report name & ": nanosecond field changed"
          severity failure;
        assert set_timestamp_s.abs_change = '1'
          report name & ": abs_change not flagged"
          severity failure;
      end if;
      wait until falling_edge(clock_s);
      assert set_s = '0'
        report name & ": set_o lasts more than one cycle"
        severity failure;
    end procedure;
  begin
    done_s(0) <= '0';
    enable_s <= '1';
    second_valid_s <= '0';
    tick_s <= '0';
    second_s <= (others => '0');
    timestamp_s.second <= (others => '0');
    timestamp_s.nanosecond <= (others => '0');
    timestamp_s.abs_change <= '0';
    wait until reset_n_s = '1';
    cycle;
    cycle;

    -- Not armed: a tick alone changes nothing.
    tick("unarmed", 5, 20000, false);

    -- Boundary already passed when the tick comes: the second shown
    -- is the tick's epoch.
    announce(1000);
    tick("after boundary", 5, 20000, true, 1001);

    -- Boundary about to pass: the second shown is the previous one.
    announce(1000);
    tick("before boundary", 5, 999980000, true, 1000);

    -- Too far from a boundary to tell.
    announce(1000);
    tick("ambiguous", 5, 500000000, false);

    -- Already right on either side: nothing to set.
    announce(1000);
    tick("right after", 1001, 20000, false);
    announce(1000);
    tick("right before", 1000, 999980000, false);

    -- A label arms exactly one tick.
    announce(1000);
    tick("first", 5, 20000, true, 1001);
    tick("second", 5, 20000, false);

    -- Disabled: labels do not arm.
    enable_s <= '0';
    announce(1000);
    tick("disabled", 5, 20000, false);
    enable_s <= '1';

    done_s(0) <= '1';
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
