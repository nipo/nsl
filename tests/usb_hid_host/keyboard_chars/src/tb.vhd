library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;
use nsl_simulation.control.all;

entity tb is
end entity;

architecture beh of tb is

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;

  signal event_s: keyboard_event_t;
  signal event_valid_s: std_ulogic := '0';
  signal event_ready_s: std_ulogic;

  signal data_s: nsl_amba.axi4_stream.bus_t;
  signal consumer_ready_s: boolean := true;

  signal rx_count_s: natural := 0;
  signal rx_last_s: byte := x"00";

  signal done_s: boolean := false;

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

  dut: hid_host_keyboard_chars
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      event_i => event_s,
      valid_i => event_valid_s,
      ready_o => event_ready_s,
      data_o => data_s.m,
      data_i => data_s.s
      );

  data_s.s <= accept(report_cfg_c, consumer_ready_s);

  collector: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if is_valid(report_cfg_c, data_s.m) and is_ready(report_cfg_c, data_s.s) then
        assert not is_last(report_cfg_c, data_s.m)
          report "last asserted on character stream"
          severity failure;
        rx_last_s <= bytes(report_cfg_c, data_s.m)(0);
        rx_count_s <= rx_count_s + 1;
      end if;
    end if;
  end process;

  stim: process is
    variable rx_expected: natural := 0;

    procedure press(code: byte; modifiers: byte := x"00") is
    begin
      wait until falling_edge(clock_s);
      event_s <= (release => false, code => code, modifiers => modifiers);
      event_valid_s <= '1';
      wait until rising_edge(clock_s) and event_ready_s = '1' for 2 us;
      assert event_ready_s = '1'
        report "event was not accepted"
        severity failure;
      wait until falling_edge(clock_s);
      event_valid_s <= '0';
    end procedure;

    procedure release(code: byte; modifiers: byte := x"00") is
    begin
      wait until falling_edge(clock_s);
      event_s <= (release => true, code => code, modifiers => modifiers);
      event_valid_s <= '1';
      wait until rising_edge(clock_s) and event_ready_s = '1' for 2 us;
      assert event_ready_s = '1'
        report "release event was not accepted"
        severity failure;
      wait until falling_edge(clock_s);
      event_valid_s <= '0';
    end procedure;

    procedure char_expect(name: string; expected: byte) is
    begin
      rx_expected := rx_expected + 1;
      if rx_count_s /= rx_expected then
        wait until rx_count_s = rx_expected for 2 us;
      end if;
      assert rx_count_s = rx_expected
        report name & ": no character emitted"
        severity failure;
      assert rx_last_s = expected
        report name & ": got " & integer'image(to_integer(unsigned(rx_last_s)))
        & ", expected " & integer'image(to_integer(unsigned(expected)))
        severity failure;
    end procedure;

    procedure press_expect(name: string;
                           code: byte;
                           modifiers: byte;
                           expected: byte) is
    begin
      press(code, modifiers);
      char_expect(name, expected);
    end procedure;

  begin
    event_s <= (release => false, code => x"00", modifiers => x"00");
    wait until reset_n_s = '1';

    press_expect("d", x"07", x"00", x"64");
    press_expect("lshift d", x"07", x"02", x"44");
    press_expect("rshift d", x"07", x"20", x"44");

    press_expect("1", x"1e", x"00", x"31");
    press_expect("shift 1", x"1e", x"02", x"21");

    press_expect("ctrl c", x"06", x"01", x"03");
    press_expect("rctrl rshift c", x"06", x"30", x"03");

    press_expect("enter", x"28", x"00", x"0d");
    press_expect("backspace", x"2a", x"00", x"08");
    press_expect("space", x"2c", x"00", x"20");
    press_expect("escape", x"29", x"00", x"1b");
    press_expect("tab", x"2b", x"00", x"09");

    -- Unmapped and non-emitting events, checked by the sentinel press
    -- that follows being the next byte on the stream.
    press(x"3a", x"00");
    press(x"39", x"00");
    press(x"e1", x"02");
    release(x"07", x"00");
    press_expect("sentinel after silent events", x"07", x"00", x"64");

    wait until falling_edge(clock_s);
    consumer_ready_s <= false;
    press(x"04", x"00");

    wait until falling_edge(clock_s);
    event_s <= (release => false, code => x"05", modifiers => x"00");
    event_valid_s <= '1';
    for i in 0 to 9 loop
      wait until rising_edge(clock_s);
      assert event_ready_s = '0'
        report "ready_o asserted while a character is pending"
        severity failure;
    end loop;

    wait until falling_edge(clock_s);
    consumer_ready_s <= true;
    char_expect("held character", x"61");

    wait until rising_edge(clock_s) and event_ready_s = '1' for 2 us;
    assert event_ready_s = '1'
      report "queued event was not accepted after release of backpressure"
      severity failure;
    wait until falling_edge(clock_s);
    event_valid_s <= '0';
    char_expect("character after backpressure", x"62");

    wait until falling_edge(clock_s);
    wait until falling_edge(clock_s);
    assert rx_count_s = rx_expected
      report "extra characters were emitted"
      severity failure;

    done_s <= true;
    terminate(0);
    wait;
  end process;

end architecture;
