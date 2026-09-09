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

  -- Typematic repeat, to insert between hid_host_keyboard_events and
  -- a consumer that wants held keys to auto-repeat (USB keyboards do
  -- not repeat on their own).
  --
  -- All events pass through unchanged, input events taking priority
  -- over synthetic ones.  The most recently pressed non-modifier key
  -- arms the repeat; after delay_ms_c it emits synthetic press
  -- events of that code every period_ms_c, carrying the latest
  -- modifier state seen, so modifiers changed mid-repeat apply.  The
  -- release of the armed code cancels the repeat, even one waiting
  -- unsent; pressing another key re-arms on the new code.  Modifier
  -- events (codes 0xe0 to 0xe7) neither arm nor cancel.
  component hid_host_keyboard_repeat is
    generic(
      clock_rate_c: natural := 12_000_000;
      delay_ms_c: natural := 400;
      period_ms_c: natural := 60
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      event_i: in keyboard_event_t;
      valid_i: in std_ulogic;
      ready_o: out std_ulogic;

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

  -- Multi-byte sequences for keys that have no single character,
  -- indexed by HID keyboard-page usage.  Length 0 means no sequence:
  -- the key falls back to the keymap.
  constant sequence_length_max_c: natural := 5;

  type key_sequence_t is
  record
    length: natural range 0 to sequence_length_max_c;
    data: string(1 to sequence_length_max_c);
  end record;

  type sequence_map_t is array (0 to 103) of key_sequence_t;

  -- VT/xterm sequences: arrows, Home, End, Insert, Delete, PgUp,
  -- PgDn, F1 to F12.
  constant sequences_vt_c: sequence_map_t;
  -- No sequences at all, every key goes through the keymap.
  constant sequences_none_c: sequence_map_t;

  -- Translates press events to a byte stream (report_cfg_c layout,
  -- no framing: last never set).
  --
  -- A key with a sequence_c entry emits the sequence, modifiers
  -- ignored.  Otherwise release events and codes outside the keymap
  -- are dropped, shift selects the shifted column, control turns a
  -- base character in the 0x40 to 0x7e range into its 0x00 to 0x1f
  -- control character, and, when alt_sends_escape_c is true, alt
  -- prefixes the emitted character with escape.  GUI and Caps Lock
  -- are ignored.
  component hid_host_keyboard_chars is
    generic(
      keymap_c: keymap_t := keymap_us_c;
      sequences_c: sequence_map_t := sequences_vt_c;
      alt_sends_escape_c: boolean := true
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

  constant esc_c: character := character'val(27);

  constant no_sequence_c: key_sequence_t :=
    (length => 0, data => (others => nul_c));

  function seq(s: string) return key_sequence_t is
    variable ret: key_sequence_t := no_sequence_c;
  begin
    ret.length := s'length;
    ret.data(1 to s'length) := s;
    return ret;
  end function;

  function sequences_vt_build return sequence_map_t is
    variable ret: sequence_map_t := (others => no_sequence_c);
  begin
    -- F1 to F4 are SS3 sequences, F5 to F12 CSI ones with the vt220
    -- numbering.
    ret(58) := seq(esc_c & "OP");
    ret(59) := seq(esc_c & "OQ");
    ret(60) := seq(esc_c & "OR");
    ret(61) := seq(esc_c & "OS");
    ret(62) := seq(esc_c & "[15~");
    ret(63) := seq(esc_c & "[17~");
    ret(64) := seq(esc_c & "[18~");
    ret(65) := seq(esc_c & "[19~");
    ret(66) := seq(esc_c & "[20~");
    ret(67) := seq(esc_c & "[21~");
    ret(68) := seq(esc_c & "[23~");
    ret(69) := seq(esc_c & "[24~");
    ret(73) := seq(esc_c & "[2~");
    ret(74) := seq(esc_c & "[H");
    ret(75) := seq(esc_c & "[5~");
    ret(76) := seq(esc_c & "[3~");
    ret(77) := seq(esc_c & "[F");
    ret(78) := seq(esc_c & "[6~");
    ret(79) := seq(esc_c & "[C");
    ret(80) := seq(esc_c & "[D");
    ret(81) := seq(esc_c & "[B");
    ret(82) := seq(esc_c & "[A");
    return ret;
  end function;

  constant sequences_vt_c: sequence_map_t := sequences_vt_build;
  constant sequences_none_c: sequence_map_t := (others => no_sequence_c);

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
