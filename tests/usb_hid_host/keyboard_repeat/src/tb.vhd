library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_usb, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;
use nsl_simulation.control.all;

entity tb is
end entity;

architecture beh of tb is

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;

  signal in_event_s: keyboard_event_t := (release => false,
                                          code => x"00",
                                          modifiers => x"00");
  signal in_valid_s: std_ulogic := '0';
  signal in_ready_s: std_ulogic;

  signal out_event_s: keyboard_event_t;
  signal out_valid_s: std_ulogic;
  signal out_ready_s: std_ulogic := '0';

  signal done_s: boolean := false;

  constant clock_rate_c: natural := 1_000_000;
  constant delay_ms_c: natural := 4;
  constant period_ms_c: natural := 2;

  -- Duration of one millisecond of the DUT's time base: 1000 cycles
  -- of the 10 ns clock.
  constant ms_c: time := 10 us;
  constant get_timeout_c: time := 10 * ms_c;

begin

  clock_gen: process is
  begin
    while not done_s loop
      clock_s <= '0';
      wait for 5 ns;
      clock_s <= '1';
      wait for 5 ns;
    end loop;
    wait;
  end process;

  reset_n_s <= '0', '1' after 30 ns;

  dut: hid_host_keyboard_repeat
    generic map(
      clock_rate_c => clock_rate_c,
      delay_ms_c => delay_ms_c,
      period_ms_c => period_ms_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      event_i => in_event_s,
      valid_i => in_valid_s,
      ready_o => in_ready_s,
      event_o => out_event_s,
      valid_o => out_valid_s,
      ready_i => out_ready_s
      );

  stim: process is

    variable last_time: time := 0 ns;
    variable t0, t1, t2: time;

    procedure event_send(release: boolean;
                         code: natural;
                         modifiers: natural) is
    begin
      wait until falling_edge(clock_s);
      in_event_s <= keyboard_event_t'(release => release,
                                      code => to_byte(code),
                                      modifiers => to_byte(modifiers));
      in_valid_s <= '1';
      wait until rising_edge(clock_s) and in_ready_s = '1'
        for get_timeout_c;
      assert in_ready_s = '1'
        report "input event was never accepted"
        severity failure;
      wait until falling_edge(clock_s);
      in_valid_s <= '0';
    end procedure;

    procedure event_get(name: string;
                        release: boolean;
                        code: natural;
                        modifiers: natural) is
    begin
      wait until rising_edge(clock_s) and out_valid_s = '1'
        for get_timeout_c;

      assert out_valid_s = '1'
        report name & ": no event came"
        severity failure;
      assert out_event_s.release = release
        report name & ": wrong direction for code "
        & integer'image(to_integer(out_event_s.code))
        severity failure;
      assert out_event_s.code = to_byte(code)
        report name & ": got code "
        & integer'image(to_integer(out_event_s.code))
        severity failure;
      assert out_event_s.modifiers = to_byte(modifiers)
        report name & ": got modifiers "
        & integer'image(to_integer(out_event_s.modifiers))
        severity failure;

      last_time := now;

      wait until falling_edge(clock_s);
      out_ready_s <= '1';
      wait until falling_edge(clock_s);
      out_ready_s <= '0';
    end procedure;

    procedure quiet(name: string;
                    duration: time) is
    begin
      wait for duration;

      assert out_valid_s = '0'
        report name & ": unexpected event, code "
        & integer'image(to_integer(out_event_s.code))
        severity failure;
    end procedure;

    procedure delay_check(name: string;
                          measured: time;
                          low: time;
                          high: time) is
    begin
      assert low <= measured and measured <= high
        report name & ": interval " & time'image(measured)
        & " outside " & time'image(low) & " to " & time'image(high)
        severity failure;
    end procedure;

  begin
    wait until reset_n_s = '1';

    -- A key held for less than the delay only yields its own events.
    event_send(false, 16#07#, 0);
    event_get("tap press", false, 16#07#, 0);
    event_send(true, 16#07#, 0);
    event_get("tap release", true, 16#07#, 0);
    quiet("tap settle", 6 * ms_c);

    -- A held key repeats after the delay, then every period, and
    -- stops on release.
    event_send(false, 16#07#, 0);
    event_get("hold press", false, 16#07#, 0);
    t0 := last_time;

    event_get("hold repeat 1", false, 16#07#, 0);
    t1 := last_time;
    delay_check("hold repeat 1", t1 - t0, 3 * ms_c - 1 us, 5 * ms_c);

    event_get("hold repeat 2", false, 16#07#, 0);
    t2 := last_time;
    delay_check("hold repeat 2", t2 - t1, ms_c + 1 us, 3 * ms_c);

    event_get("hold repeat 3", false, 16#07#, 0);
    delay_check("hold repeat 3", last_time - t2, ms_c + 1 us, 3 * ms_c);

    event_send(true, 16#07#, 0);
    event_get("hold release", true, 16#07#, 0);
    quiet("hold settle", 6 * ms_c);

    -- Pressing another key moves the repeat to it, the first one
    -- never repeats again although it is still held.
    event_send(false, 16#07#, 0);
    event_get("rearm press 07", false, 16#07#, 0);
    event_get("rearm repeat 07", false, 16#07#, 0);

    event_send(false, 16#09#, 0);
    event_get("rearm press 09", false, 16#09#, 0);
    t0 := last_time;

    event_get("rearm repeat 09", false, 16#09#, 0);
    t1 := last_time;
    delay_check("rearm repeat 09", t1 - t0, 3 * ms_c - 1 us, 5 * ms_c);

    event_get("rearm repeat 09 again", false, 16#09#, 0);
    delay_check("rearm repeat 09 again", last_time - t1,
                ms_c + 1 us, 3 * ms_c);

    -- Releasing a key that is not the armed one must not stop the
    -- ongoing repeat.
    event_send(true, 16#07#, 0);
    event_get("other release 07", true, 16#07#, 0);
    event_get("repeat 09 survives", false, 16#09#, 0);

    event_send(false, 16#07#, 0);
    event_get("rearm press 07 back", false, 16#07#, 0);
    event_send(true, 16#07#, 0);
    event_get("rearm release 07 back", true, 16#07#, 0);

    event_send(true, 16#09#, 0);
    event_get("rearm release 09", true, 16#09#, 0);
    quiet("rearm settle", 6 * ms_c);

    event_send(true, 16#07#, 0);
    event_get("rearm release 07", true, 16#07#, 0);
    quiet("rearm final", 6 * ms_c);

    -- Modifiers pressed or released during a repeat pass through,
    -- change the modifier byte of later synthetic events, and touch
    -- neither the armed code nor the timer.
    event_send(false, 16#04#, 0);
    event_get("modifier press 04", false, 16#04#, 0);
    event_get("modifier repeat plain", false, 16#04#, 0);
    t0 := last_time;

    event_send(false, 16#e1#, 16#02#);
    event_get("shift press", false, 16#e1#, 16#02#);

    event_get("modifier repeat shifted", false, 16#04#, 16#02#);
    t1 := last_time;
    delay_check("shift press keeps timer", t1 - t0, ms_c + 1 us, 3 * ms_c);

    event_get("modifier repeat shifted again", false, 16#04#, 16#02#);
    t2 := last_time;

    event_send(true, 16#e1#, 0);
    event_get("shift release", true, 16#e1#, 0);

    event_get("modifier repeat unshifted", false, 16#04#, 0);
    delay_check("shift release keeps repeat", last_time - t2,
                ms_c + 1 us, 3 * ms_c);

    event_send(true, 16#04#, 0);
    event_get("modifier release 04", true, 16#04#, 0);
    quiet("modifier settle", 6 * ms_c);

    -- A synthetic event waiting for a stalled consumer does not block
    -- the input side, and the release of the armed code takes its
    -- place.
    event_send(false, 16#05#, 0);
    event_get("cancel press", false, 16#05#, 0);

    wait until rising_edge(clock_s) and out_valid_s = '1'
      for get_timeout_c;
    assert out_valid_s = '1'
      report "cancel: repeat did not come"
      severity failure;
    assert out_event_s.code = to_byte(16#05#) and not out_event_s.release
      report "cancel: pending event is not the repeat"
      severity failure;

    event_send(true, 16#05#, 0);
    event_get("cancel release", true, 16#05#, 0);
    quiet("cancel settle", 6 * ms_c);

    done_s <= true;
    terminate(0);
    wait;
  end process;

end architecture;
