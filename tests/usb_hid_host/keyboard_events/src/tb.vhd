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

  signal clear_s: std_ulogic := '0';
  signal modifiers_s: byte := x"00";
  signal keys_s: byte_string(0 to 5) := (others => x"00");
  signal valid_s: std_ulogic := '0';

  signal event_s: keyboard_event_t;
  signal event_valid_s: std_ulogic;
  signal ready_s: std_ulogic := '0';

  signal done_s: boolean := false;

  constant none_c: byte_string(0 to 5) := (others => x"00");

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

  dut: hid_host_keyboard_events
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      clear_i => clear_s,
      modifiers_i => modifiers_s,
      keys_i => keys_s,
      valid_i => valid_s,
      event_o => event_s,
      valid_o => event_valid_s,
      ready_i => ready_s
      );

  stim: process is

    procedure report_send(modifiers: byte;
                          keys: byte_string(0 to 5)) is
    begin
      wait until falling_edge(clock_s);
      modifiers_s <= modifiers;
      keys_s <= keys;
      valid_s <= '1';
      wait until falling_edge(clock_s);
      valid_s <= '0';
    end procedure;

    procedure clear_set(value: std_ulogic) is
    begin
      wait until falling_edge(clock_s);
      clear_s <= value;
    end procedure;

    procedure event_expect(name: string;
                           release: boolean;
                           code: natural;
                           modifiers: natural) is
    begin
      wait until rising_edge(clock_s) and event_valid_s = '1' for 5 us;

      assert event_valid_s = '1'
        report name & ": no event came"
        severity failure;
      assert event_s.release = release
        report name & ": wrong direction for code "
        & integer'image(to_integer(event_s.code))
        severity failure;
      assert event_s.code = to_byte(code)
        report name & ": got code "
        & integer'image(to_integer(event_s.code))
        severity failure;
      assert event_s.modifiers = to_byte(modifiers)
        report name & ": got modifiers "
        & integer'image(to_integer(event_s.modifiers))
        severity failure;

      wait until falling_edge(clock_s);
      ready_s <= '1';
      wait until falling_edge(clock_s);
      ready_s <= '0';
    end procedure;

    procedure event_none(name: string) is
    begin
      wait for 3 us;

      assert event_valid_s = '0'
        report name & ": unexpected event, code "
        & integer'image(to_integer(event_s.code))
        severity failure;
    end procedure;

  begin
    wait until reset_n_s = '1';

    -- Slot movement: a key kept held across reports must not
    -- re-emit when it changes slot.
    report_send(x"00", none_c);
    event_none("idle report");

    report_send(x"00", from_hex("070000000000"));
    event_expect("d press", false, 16#07#, 0);

    report_send(x"00", from_hex("070900000000"));
    event_expect("f press", false, 16#09#, 0);

    report_send(x"00", from_hex("090000000000"));
    event_expect("d release", true, 16#07#, 0);
    event_none("f kept held");

    report_send(x"00", none_c);
    event_expect("f release", true, 16#09#, 0);
    event_none("all released");

    -- Two presses at once
    report_send(x"00", from_hex("040500000000"));
    event_expect("dual press 1", false, 16#04#, 0);
    event_expect("dual press 2", false, 16#05#, 0);
    event_none("dual settle");

    report_send(x"00", none_c);
    event_expect("dual release 1", true, 16#04#, 0);
    event_expect("dual release 2", true, 16#05#, 0);

    -- Release and press in the same report
    report_send(x"00", from_hex("040000000000"));
    event_expect("swap setup", false, 16#04#, 0);

    report_send(x"00", from_hex("050000000000"));
    event_expect("swap release", true, 16#04#, 0);
    event_expect("swap press", false, 16#05#, 0);

    report_send(x"00", none_c);
    event_expect("swap cleanup", true, 16#05#, 0);

    -- Modifiers
    report_send(x"02", none_c);
    event_expect("shift press", false, 16#e1#, 16#02#);

    report_send(x"02", from_hex("040000000000"));
    event_expect("shifted key press", false, 16#04#, 16#02#);

    report_send(x"00", from_hex("040000000000"));
    event_expect("shift release", true, 16#e1#, 16#00#);

    report_send(x"00", none_c);
    event_expect("shifted key release", true, 16#04#, 0);
    event_none("modifier settle");

    -- Rollover: error codes are not keys
    report_send(x"00", from_hex("070900000000"));
    event_expect("rollover setup 1", false, 16#07#, 0);
    event_expect("rollover setup 2", false, 16#09#, 0);

    report_send(x"00", from_hex("010101010101"));
    event_expect("rollover release 1", true, 16#07#, 0);
    event_expect("rollover release 2", true, 16#09#, 0);
    event_none("rollover settle");

    report_send(x"00", from_hex("070900000000"));
    event_expect("rollover repress 1", false, 16#07#, 0);
    event_expect("rollover repress 2", false, 16#09#, 0);

    report_send(x"00", none_c);
    event_expect("rollover cleanup 1", true, 16#07#, 0);
    event_expect("rollover cleanup 2", true, 16#09#, 0);

    -- Backpressure, then overwrite of the pending report while
    -- stalled: the diff resumes against the latest report only.
    report_send(x"00", from_hex("040000000000"));
    wait for 2 us;
    assert event_valid_s = '1'
      report "stalled event did not wait"
      severity failure;
    assert event_s.code = to_byte(16#04#)
      report "stalled event has wrong code"
      severity failure;

    report_send(x"00", from_hex("040500000000"));
    report_send(x"00", from_hex("060000000000"));

    event_expect("stalled press", false, 16#04#, 0);
    event_expect("overwrite release", true, 16#04#, 0);
    event_expect("overwrite press", false, 16#06#, 0);
    event_none("overwrite settle");

    report_send(x"00", none_c);
    event_expect("overwrite cleanup", true, 16#06#, 0);

    -- clear_i releases everything held and makes reports received
    -- while asserted disappear.
    report_send(x"02", from_hex("040000000000"));
    event_expect("clear setup 1", false, 16#e1#, 16#02#);
    event_expect("clear setup 2", false, 16#04#, 16#02#);

    clear_set('1');
    report_send(x"00", from_hex("050000000000"));
    clear_set('0');

    event_expect("clear release 1", true, 16#e1#, 16#00#);
    event_expect("clear release 2", true, 16#04#, 16#00#);
    event_none("clear settle");

    report_send(x"00", from_hex("050000000000"));
    event_expect("press after clear", false, 16#05#, 0);

    report_send(x"00", none_c);
    event_expect("release after clear", true, 16#05#, 0);
    event_none("final settle");

    done_s <= true;
    terminate(0);
    wait;
  end process;

end architecture;
