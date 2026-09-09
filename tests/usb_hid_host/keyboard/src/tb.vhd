library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_usb;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_usb.io.all;
use nsl_usb.hid_host.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;

entity tb is
end entity;

architecture beh of tb is

  constant device_descriptor_c: byte_string
    := from_hex("120100010000000821436587000100000001");

  constant config_descriptor_c: byte_string := from_hex(
    "090222000101008032"
    & "090400000103010100"
    & "092111010001223f00"
    & "0705810308000a");

  -- Left shift held with keys A, B, C, D down.
  constant report_c: byte_string(0 to 7) := from_hex("0200040506070000");

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;

  -- One keyboard wrapper accepting any VID/PID, one requiring a VID
  -- the device does not have.  Each has its own bus and device.
  signal match_c_s, reject_c_s: usb_io_c;
  signal match_s_s, reject_s_s: usb_io_s;

  signal match_identity_s, reject_identity_s: device_identity_t;
  signal match_status_s, reject_status_s: hid_host_status_t;
  signal match_matched_s, reject_matched_s: std_ulogic;

  signal match_modifiers_s: byte;
  signal match_keys_s: byte_string(0 to 5);
  signal match_valid_s, reject_valid_s: std_ulogic;
  signal reject_modifiers_s: byte;
  signal reject_keys_s: byte_string(0 to 5);

  signal match_report_valid_s, reject_report_valid_s: std_ulogic := '0';

  signal match_count_s, reject_count_s: natural := 0;

begin

  clock_gen: process is
  begin
    clock_s <= '0';
    wait for 41667 ps;
    clock_s <= '1';
    wait for 41666 ps;
  end process;

  reset_n_s <= '0', '1' after 500 ns;

  match_dut: nsl_usb.hid_host.hid_host_keyboard
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      bus_o => match_c_s,
      bus_i => match_s_s,
      identity_o => match_identity_s,
      status_o => match_status_s,
      matched_o => match_matched_s,
      modifiers_o => match_modifiers_s,
      keys_o => match_keys_s,
      valid_o => match_valid_s
      );

  match_device: nsl_usb.ls_bfm.ls_device_bfm
    generic map(
      device_descriptor_c => device_descriptor_c,
      config_descriptor_c => config_descriptor_c
      )
    port map(
      host_i => match_c_s,
      host_o => match_s_s,
      report_data_i => report_c,
      report_length_i => 8,
      report_valid_i => match_report_valid_s
      );

  reject_dut: nsl_usb.hid_host.hid_host_keyboard
    generic map(
      expected_vid_c => x"1111"
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      bus_o => reject_c_s,
      bus_i => reject_s_s,
      identity_o => reject_identity_s,
      status_o => reject_status_s,
      matched_o => reject_matched_s,
      modifiers_o => reject_modifiers_s,
      keys_o => reject_keys_s,
      valid_o => reject_valid_s
      );

  reject_device: nsl_usb.ls_bfm.ls_device_bfm
    generic map(
      device_descriptor_c => device_descriptor_c,
      config_descriptor_c => config_descriptor_c
      )
    port map(
      host_i => reject_c_s,
      host_o => reject_s_s,
      report_data_i => report_c,
      report_length_i => 8,
      report_valid_i => reject_report_valid_s
      );

  counters: process is
  begin
    wait until rising_edge(clock_s);
    if match_valid_s = '1' then
      match_count_s <= match_count_s + 1;
    end if;
    if reject_valid_s = '1' then
      reject_count_s <= reject_count_s + 1;
    end if;
  end process;

  stim: process is
  begin
    log_info("* Enumeration of both keyboards");

    wait until match_identity_s.valid and reject_identity_s.valid for 500 ms;
    assert match_identity_s.valid and reject_identity_s.valid
      report "Enumeration did not complete"
      severity failure;

    -- matched_o derives combinatorially from identity_o; let it
    -- settle past the delta where valid rose.
    wait for 1 us;

    assert match_matched_s = '1'
      report "Wildcard wrapper does not match a boot keyboard"
      severity failure;
    assert reject_matched_s = '0'
      report "VID-restricted wrapper matched a foreign device"
      severity failure;

    log_info("* Report through the matching wrapper");

    match_report_valid_s <= '1';
    wait until match_count_s = 1 for 50 ms;
    assert match_count_s = 1
      report "No report came through the matching wrapper"
      severity failure;
    match_report_valid_s <= '0';

    assert match_modifiers_s = x"02"
      report "Modifiers are " & to_hex_string(match_modifiers_s)
      severity failure;
    assert match_keys_s = from_hex("040506070000")
      report "Keys are " & to_hex_string(match_keys_s)
      severity failure;

    log_info("* Report blocked by the rejecting wrapper");

    reject_report_valid_s <= '1';
    wait for 50 ms;
    reject_report_valid_s <= '0';

    assert reject_count_s = 0
      report "A report leaked through a non-matched wrapper"
      severity failure;

    terminate(0);
  end process;

end architecture;
