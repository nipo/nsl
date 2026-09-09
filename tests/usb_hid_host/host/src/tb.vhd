library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_usb.io.all;
use nsl_usb.hid_host.all;
use nsl_usb.hid_program.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;

entity tb is
end entity;

architecture beh of tb is

  -- USB 1.10, class-per-interface, EP0 MPS 8, VID 4321, PID 8765,
  -- device 1.00, no strings, one configuration.
  constant device_descriptor_c: byte_string
    := from_hex("120100010000000821436587000100000001");

  constant config_descriptor_c: byte_string := from_hex(
    -- Configuration: 34 bytes in total, one interface, bus powered, 100 mA
    "090222000101008032"
    -- Interface 0: HID (3), boot (1), keyboard (1), one endpoint
    & "090400000103010100"
    -- HID 1.11, one report descriptor of 63 bytes
    & "092111010001223f00"
    -- Endpoint 1 IN, interrupt, 8 bytes, 10 ms interval
    & "0705810308000a");

  constant report_a_c: byte_string(0 to 7) := from_hex("0000040506000000");
  constant report_b_c: byte_string(0 to 7) := from_hex("0200070000000000");
  constant report_c_c: byte_string(0 to 7) := from_hex("0000160000000000");

  constant poll_interval_ms_c: natural := 2;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;

  signal host_c_s: usb_io_c;
  signal host_s_s: usb_io_s;

  signal identity_s: device_identity_t;
  signal status_s: hid_host_status_t;
  signal report_s: nsl_amba.axi4_stream.bus_t;

  signal present_s: std_ulogic := '1';
  signal report_data_s: byte_string(0 to 7) := (others => x"00");
  signal report_length_s: natural range 0 to 8 := 0;
  signal report_valid_s: std_ulogic := '0';
  signal report_ready_s: std_ulogic;
  signal crc_corrupt_s: std_ulogic := '0';

  -- Last frame collected on report_o, and how many were collected.
  signal frame_s: byte_string(0 to 7) := (others => x"00");
  signal frame_len_s: natural := 0;
  signal frame_count_s: natural := 0;

begin

  clock_gen: process is
  begin
    clock_s <= '0';
    wait for 41667 ps;
    clock_s <= '1';
    wait for 41666 ps;
  end process;

  reset_n_s <= '0', '1' after 500 ns;

  dut: nsl_usb.hid_host.hid_host_engine
    generic map(
      program_c => hid_program(hid_program_config_t'(
        poll_interval_ms => poll_interval_ms_c,
        report_length => 8,
        configuration_value => 1)),
      clock_rate_c => 12_000_000
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      bus_o => host_c_s,
      bus_i => host_s_s,
      identity_o => identity_s,
      status_o => status_s,
      report_o => report_s.m,
      report_i => report_s.s
      );

  device: nsl_usb.ls_bfm.ls_device_bfm
    generic map(
      device_descriptor_c => device_descriptor_c,
      config_descriptor_c => config_descriptor_c,
      interrupt_ep_c => 1
      )
    port map(
      host_i => host_c_s,
      host_o => host_s_s,
      present_i => present_s,
      report_data_i => report_data_s,
      report_length_i => report_length_s,
      report_valid_i => report_valid_s,
      report_ready_o => report_ready_s,
      crc_corrupt_i => crc_corrupt_s
      );

  report_s.s <= accept(report_cfg_c, true);

  collector: process is
    variable buf: byte_string(0 to 7) := (others => x"00");
    variable count: natural := 0;
  begin
    wait until rising_edge(clock_s);

    if is_valid(report_cfg_c, report_s.m) then
      if count < buf'length then
        buf(count) := bytes(report_cfg_c, report_s.m)(0);
      end if;
      count := count + 1;

      if is_last(report_cfg_c, report_s.m) then
        frame_s <= buf;
        frame_len_s <= count;
        frame_count_s <= frame_count_s + 1;
        buf := (others => x"00");
        count := 0;
      end if;
    end if;
  end process;

  watchdog_check: process is
  begin
    wait until rising_edge(clock_s);

    assert status_s.error = '0'
      report "Protocol watchdog fired"
      severity failure;
  end process;

  stim: process is
    variable seen: natural;
  begin
    log_info("* Enumeration");

    wait until identity_s.valid for 500 ms;
    assert identity_s.valid
      report "Device was not enumerated in time"
      severity failure;

    assert identity_s.vid = x"4321"
      report "Vendor id is " & to_hex_string(std_ulogic_vector(identity_s.vid))
      severity failure;
    assert identity_s.pid = x"8765"
      report "Product id is " & to_hex_string(std_ulogic_vector(identity_s.pid))
      severity failure;
    assert identity_s.if_class = x"03"
      report "Interface class is " & to_hex_string(identity_s.if_class)
      severity failure;
    assert identity_s.if_subclass = x"01"
      report "Interface subclass is " & to_hex_string(identity_s.if_subclass)
      severity failure;
    assert identity_s.if_protocol = x"01"
      report "Interface protocol is " & to_hex_string(identity_s.if_protocol)
      severity failure;

    log_info("* First interrupt report");

    seen := frame_count_s;
    report_data_s <= report_a_c;
    report_length_s <= 8;
    report_valid_s <= '1';

    wait until frame_count_s /= seen for 50 ms;
    assert frame_count_s = seen + 1
      report "No report frame after the first poll"
      severity failure;
    assert frame_len_s = 8
      report "First report frame is " & to_string(frame_len_s) & " bytes long"
      severity failure;
    assert frame_s = report_a_c
      report "First report payload is " & to_hex_string(frame_s)
      severity failure;

    wait for 100 us;
    report_valid_s <= '0';

    log_info("* Second interrupt report");

    seen := frame_count_s;
    report_data_s <= report_b_c;
    report_length_s <= 8;
    report_valid_s <= '1';

    wait until frame_count_s /= seen for 50 ms;
    assert frame_count_s = seen + 1
      report "No report frame for the second report"
      severity failure;
    assert frame_len_s = 8
      report "Second report frame is " & to_string(frame_len_s) & " bytes long"
      severity failure;
    assert frame_s = report_b_c
      report "Second report payload is " & to_hex_string(frame_s)
      severity failure;

    wait for 100 us;
    report_valid_s <= '0';

    log_info("* Report with a corrupted CRC16");

    seen := frame_count_s;
    crc_corrupt_s <= '1';
    report_data_s <= report_c_c;
    report_length_s <= 8;
    report_valid_s <= '1';

    wait for 4 * poll_interval_ms_c * 1 ms;
    assert frame_count_s = seen
      report "A corrupted report was handed out"
      severity failure;

    log_info("* Retransmission once the corruption stops");

    crc_corrupt_s <= '0';

    wait until frame_count_s /= seen for 50 ms;
    assert frame_count_s = seen + 1
      report "Corrupted report was not retransmitted"
      severity failure;
    assert frame_len_s = 8
      report "Retransmitted frame is " & to_string(frame_len_s) & " bytes long"
      severity failure;
    assert frame_s = report_c_c
      report "Retransmitted payload is " & to_hex_string(frame_s)
      severity failure;

    wait for 100 us;
    report_valid_s <= '0';

    log_info("* Disconnection");

    present_s <= '0';

    wait until not identity_s.valid for 10 * poll_interval_ms_c * 1 ms;
    assert not identity_s.valid
      report "Disconnection went unnoticed"
      severity failure;

    log_info("* Reconnection");

    present_s <= '1';

    wait until identity_s.valid for 500 ms;
    assert identity_s.valid
      report "Device was not enumerated again"
      severity failure;

    assert identity_s.vid = x"4321" and identity_s.pid = x"8765"
      report "Identity differs after re-enumeration"
      severity failure;

    log_info("* Idle with no device across a watchdog period");

    -- The idle loop executes no START and receives nothing; only the
    -- taken BZ holds the watchdog reset.  The watchdog period is
    -- 2**24 cycles, a hair under 1.4s; the error monitor catches any
    -- pulse.
    present_s <= '0';
    wait for 1500 ms;

    terminate(0);
  end process;

end architecture;
