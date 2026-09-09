library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb;
use nsl_data.bytestream.all;
use nsl_usb.ukp.all;

-- Standalone low-speed USB host for HID input devices.
--
-- hid_host_engine runs an elaboration-time-assembled microcode
-- program (see the ukp package) that enumerates the single directly
-- attached low-speed device, records its identity, and polls its
-- interrupt IN endpoint.  Each interrupt report received with a good
-- CRC is emitted as one last-delimited frame on an AXI4-Stream port.
--
-- hid_host_extractor turns report frames into parallel field values
-- described by an elaboration-time field list.
--
-- hid_host_keyboard and hid_host_mouse bundle engine and extractor
-- for boot-protocol devices.
package hid_host is

  -- Interrupt reports from low-speed devices are at most 8 bytes
  -- (low-speed maximum packet size).
  constant report_length_max_c: natural := 8;

  constant report_cfg_c: nsl_amba.axi4_stream.config_t :=
    nsl_amba.axi4_stream.config(bytes => 1, last => true);

  -- Identity register indices for the UKP SAVE instruction.
  constant save_reg_vid_l_c: natural := 0;
  constant save_reg_vid_h_c: natural := 1;
  constant save_reg_pid_l_c: natural := 2;
  constant save_reg_pid_h_c: natural := 3;
  constant save_reg_if_class_c: natural := 4;
  constant save_reg_if_subclass_c: natural := 5;
  constant save_reg_if_protocol_c: natural := 6;

  type device_identity_t is
  record
    vid: unsigned(15 downto 0);
    pid: unsigned(15 downto 0);
    if_class: byte;
    if_subclass: byte;
    if_protocol: byte;
    -- Tracks the microcode C flag: the program sets it once
    -- enumeration completed and all identity registers are written,
    -- clears it on disconnect.
    valid: boolean;
  end record;

  type hid_host_status_t is
  record
    -- Same as device_identity_t.valid.
    enumerated: boolean;
    -- Asserted for one cycle when the protocol watchdog expires and
    -- restarts the program.
    error: std_ulogic;
  end record;

  -- One extracted report field.  Fields spanning multiple bytes are
  -- read little-endian, matching HID report packing.  Bytes beyond
  -- the length of a received report read as zero.
  type field_t is
  record
    byte_offset: natural range 0 to report_length_max_c - 1;
    bit_offset: natural range 0 to 7;
    width: natural range 1 to 16;
  end record;

  constant field_count_max_c: natural := 16;
  type field_vector is array (natural range <>) of field_t;

  -- Total width of the extractor values_o port for a field list.
  function fields_width(f: field_vector) return natural;
  -- Offset of field index within values_o; the field occupies
  -- values_o(field_offset(f, index) + f(index).width - 1 downto
  -- field_offset(f, index)).
  function field_offset(f: field_vector; index: natural) return natural;

  component hid_host_engine is
    generic(
      program_c: program_t;
      clock_rate_c: natural := 12_000_000
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      bus_o: out nsl_usb.io.usb_io_c;
      bus_i: in nsl_usb.io.usb_io_s;

      identity_o: out device_identity_t;
      status_o: out hid_host_status_t;

      -- One frame per interrupt report received with a good CRC,
      -- configured as report_cfg_c.  A new report completing while
      -- the previous frame is not fully drained is dropped, so frame
      -- boundaries are always preserved.  Zero-length reports emit
      -- nothing.
      report_o: out nsl_amba.axi4_stream.master_t;
      report_i: in nsl_amba.axi4_stream.slave_t
      );
  end component;

  component hid_host_extractor is
    generic(
      fields_c: field_vector
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      report_i: in nsl_amba.axi4_stream.master_t;
      report_o: out nsl_amba.axi4_stream.slave_t;

      -- fields_width(fields_c)-1 downto 0
      values_o: out std_ulogic_vector;
      -- Pulses once per completed report.
      valid_o: out std_ulogic
      );
  end component;

  component hid_host_keyboard is
    generic(
      clock_rate_c: natural := 12_000_000;
      -- x"0000" matches any.
      expected_vid_c: unsigned(15 downto 0) := x"0000";
      expected_pid_c: unsigned(15 downto 0) := x"0000"
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      bus_o: out nsl_usb.io.usb_io_c;
      bus_i: in nsl_usb.io.usb_io_s;

      identity_o: out device_identity_t;
      status_o: out hid_host_status_t;
      -- Enumerated device is a boot-protocol keyboard and matches
      -- expected VID/PID.  Reports are dropped while not matched.
      matched_o: out std_ulogic;

      modifiers_o: out byte;
      keys_o: out byte_string(0 to 5);
      valid_o: out std_ulogic
      );
  end component;

  component hid_host_mouse is
    generic(
      clock_rate_c: natural := 12_000_000;
      expected_vid_c: unsigned(15 downto 0) := x"0000";
      expected_pid_c: unsigned(15 downto 0) := x"0000"
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      bus_o: out nsl_usb.io.usb_io_c;
      bus_i: in nsl_usb.io.usb_io_s;

      identity_o: out device_identity_t;
      status_o: out hid_host_status_t;
      matched_o: out std_ulogic;

      buttons_o: out byte;
      -- Per-report deltas, valid on valid_o pulse.
      dx_o: out signed(7 downto 0);
      dy_o: out signed(7 downto 0);
      valid_o: out std_ulogic
      );
  end component;

  -- One key transition, derived from consecutive boot reports.
  -- Modifier keys appear as their HID keyboard-page usages 0xe0 to
  -- 0xe7, matching the modifier byte bit order.
  type keyboard_event_t is
  record
    release: boolean;
    code: byte;
    -- Modifier state of the report that produced the event.
    modifiers: byte;
  end record;

  -- Turns the boot report sequence into press and release events.
  --
  -- Report slots hold a set of scancodes with no positional meaning:
  -- a scancode present in the current report but absent from the
  -- previous one is a press, the converse is a release.  Per report,
  -- releases are emitted before presses, in slot order.  Scancodes
  -- below 4 are not keys (no-event and error markers) and never
  -- produce events, so an all-ErrorRollOver phantom report reads as
  -- everything released, and its clearing re-presses the surviving
  -- keys.
  --
  -- A report arriving while the previous one is still being diffed
  -- replaces the pending one; the diff then runs against the latest
  -- state, losing only transitions fully contained in the skipped
  -- window.
  --
  -- Asserting clear_i forgets the held state, emitting a release for
  -- every held key first, so a device unplug does not leave keys
  -- stuck down.  Wire it to "not matched_o" of the wrapper.
  component hid_host_keyboard_events is
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      clear_i: in std_ulogic := '0';

      modifiers_i: in byte;
      keys_i: in byte_string(0 to 5);
      valid_i: in std_ulogic;

      event_o: out keyboard_event_t;
      valid_o: out std_ulogic;
      ready_i: in std_ulogic
      );
  end component;

  -- Keymap for hid_host_keyboard_chars, indexed by HID keyboard-page
  -- usage.  NUL means the key emits nothing.
  type keymap_entry_t is
  record
    normal: character;
    shifted: character;
  end record;

  type keymap_t is array (0 to 103) of keymap_entry_t;

  constant keymap_us_c: keymap_t;

  -- Translates press events to a byte stream (report_cfg_c layout,
  -- no framing: last never set).
  --
  -- Release events and codes outside the keymap are dropped.  Shift
  -- selects the shifted column.  Control turns a base character in
  -- the 0x40 to 0x7e range into its 0x00 to 0x1f control character.
  -- Alt, GUI and Caps Lock are ignored.
  component hid_host_keyboard_chars is
    generic(
      keymap_c: keymap_t := keymap_us_c
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      event_i: in keyboard_event_t;
      valid_i: in std_ulogic;
      ready_o: out std_ulogic;

      data_o: out nsl_amba.axi4_stream.master_t;
      data_i: in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package;

package body hid_host is

  constant nul_c: character := character'val(0);

  function keymap_us_build return keymap_t is
    variable ret: keymap_t := (others => (nul_c, nul_c));
    constant shifted_digits_c: string(1 to 9) := "!@#$%^&*(";
  begin
    for i in 0 to 25 loop
      ret(4 + i) := (character'val(character'pos('a') + i),
                     character'val(character'pos('A') + i));
    end loop;
    for i in 0 to 8 loop
      ret(30 + i) := (character'val(character'pos('1') + i),
                      shifted_digits_c(i + 1));
    end loop;
    ret(39) := ('0', ')');
    ret(40) := (character'val(13), character'val(13));
    ret(41) := (character'val(27), character'val(27));
    ret(42) := (character'val(8), character'val(8));
    ret(43) := (character'val(9), character'val(9));
    ret(44) := (' ', ' ');
    ret(45) := ('-', '_');
    ret(46) := ('=', '+');
    ret(47) := ('[', '{');
    ret(48) := (']', '}');
    ret(49) := ('\', '|');
    ret(50) := ('\', '|');
    ret(51) := (';', ':');
    ret(52) := (''', '"');
    ret(53) := ('`', '~');
    ret(54) := (',', '<');
    ret(55) := ('.', '>');
    ret(56) := ('/', '?');
    -- Keypad; Num Lock state is not tracked, keys always yield their
    -- Num Lock meaning.
    ret(84) := ('/', '/');
    ret(85) := ('*', '*');
    ret(86) := ('-', '-');
    ret(87) := ('+', '+');
    ret(88) := (character'val(13), character'val(13));
    for i in 0 to 8 loop
      ret(89 + i) := (character'val(character'pos('1') + i),
                      character'val(character'pos('1') + i));
    end loop;
    ret(98) := ('0', '0');
    ret(99) := ('.', '.');
    ret(100) := ('\', '|');
    ret(103) := ('=', '=');
    return ret;
  end function;

  constant keymap_us_c: keymap_t := keymap_us_build;

  function fields_width(f: field_vector) return natural is
    variable ret: natural := 0;
  begin
    for i in f'range loop
      ret := ret + f(i).width;
    end loop;
    return ret;
  end function;

  function field_offset(f: field_vector; index: natural) return natural is
    variable ret: natural := 0;
  begin
    assert index <= f'high
      report "Field index out of range"
      severity failure;
    for i in f'low to index - 1 loop
      ret := ret + f(i).width;
    end loop;
    return ret;
  end function;

end package body;
