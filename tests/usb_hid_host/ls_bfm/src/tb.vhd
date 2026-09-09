library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_simulation;
use nsl_usb.usb.all;
use nsl_usb.io.all;
use nsl_usb.ls_bfm.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;

entity tb is
end entity;

architecture arch of tb is

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

  constant addr0_c: device_address_t := "0000000";
  constant addr1_c: device_address_t := "0000001";
  constant ep0_c: endpoint_no_t := x"0";
  constant ep1_c: endpoint_no_t := x"1";

  constant report_a_c: byte_string(0 to 7) := from_hex("0000040506000000");
  constant report_b_c: byte_string(0 to 7) := from_hex("0000070000000000");

  signal host_c: usb_io_c;
  signal host_s: usb_io_s;

  signal report_data: byte_string(0 to 7) := (others => x"00");
  signal report_length: natural range 0 to 8 := 0;
  signal report_valid: std_ulogic := '0';
  signal report_ready: std_ulogic;
  signal crc_corrupt: std_ulogic := '0';

  signal consumed: natural := 0;

begin

  dut: nsl_usb.ls_bfm.ls_device_bfm
    generic map(
      device_descriptor_c => device_descriptor_c,
      config_descriptor_c => config_descriptor_c,
      interrupt_ep_c => 1
      )
    port map(
      host_i => host_c,
      host_o => host_s,
      present_i => '1',
      report_data_i => report_data,
      report_length_i => report_length,
      report_valid_i => report_valid,
      report_ready_o => report_ready,
      crc_corrupt_i => crc_corrupt
      );

  consumption: process is
  begin
    wait until report_ready = '1';
    consumed <= consumed + 1;
  end process;

  stim: process is
    variable setup: setup_t;
    variable rx: byte_string(0 to 63);
    variable rx_len: natural;
    variable ok: boolean;
    variable rsp: ls_in_result_t;
  begin
    ls_bus_release(host_c);
    wait for 100 us;

    -- Spec asks for at least 10 ms of SE0.  This model takes anything
    -- longer than 100 us for a reset, so a millisecond keeps the
    -- simulation short while staying well clear of a keep-alive EOP.
    ls_reset(host_c, 1 ms);

    log_info("* GET_DESCRIPTOR(device) at the default address");

    setup.direction := DEVICE_TO_HOST;
    setup.rtype := SETUP_TYPE_STANDARD;
    setup.recipient := SETUP_RECIPIENT_DEVICE;
    setup.request := REQUEST_GET_DESCRIPTOR;
    setup.value := x"0100";
    setup.index := x"0000";
    setup.length := to_unsigned(18, 16);

    ls_control_read(host_c, host_s, addr0_c, setup, rx, rx_len, ok);
    assert ok
      report "GET_DESCRIPTOR(device) failed at the default address"
      severity failure;
    assert rx_len = 18
      report "Device descriptor is " & to_string(rx_len) & " bytes long"
      severity failure;
    assert rx(8) = x"21" and rx(9) = x"43"
      report "Vendor ID mismatch"
      severity failure;
    assert rx(10) = x"65" and rx(11) = x"87"
      report "Product ID mismatch"
      severity failure;

    log_info("* SET_ADDRESS(1)");

    setup.direction := HOST_TO_DEVICE;
    setup.request := REQUEST_SET_ADDRESS;
    setup.value := x"0001";
    setup.index := x"0000";
    setup.length := x"0000";

    ls_control_write(host_c, host_s, addr0_c, setup, ok);
    assert ok
      report "SET_ADDRESS was not carried out"
      severity failure;

    ls_transfer_in(host_c, host_s, addr0_c, ep0_c, rsp);
    assert rsp.timeout
      report "Device still answers at the default address"
      severity failure;

    setup.direction := DEVICE_TO_HOST;
    setup.request := REQUEST_GET_DESCRIPTOR;
    setup.value := x"0100";
    setup.length := to_unsigned(8, 16);

    ls_control_read(host_c, host_s, addr1_c, setup, rx, rx_len, ok);
    assert ok and rx_len = 8
      report "Device does not answer at its new address"
      severity failure;
    assert rx(0) = x"12" and rx(7) = x"08"
      report "Device descriptor head is not what it was at address 0"
      severity failure;

    log_info("* GET_DESCRIPTOR(configuration)");

    setup.value := x"0200";
    setup.length := to_unsigned(34, 16);

    ls_control_read(host_c, host_s, addr1_c, setup, rx, rx_len, ok);
    assert ok
      report "GET_DESCRIPTOR(configuration) failed"
      severity failure;
    assert rx_len = 34
      report "Configuration blob is " & to_string(rx_len) & " bytes long"
      severity failure;
    assert rx(14) = x"03" and rx(15) = x"01" and rx(16) = x"01"
      report "Interface is not a boot keyboard"
      severity failure;

    log_info("* SET_CONFIGURATION(1)");

    setup.direction := HOST_TO_DEVICE;
    setup.request := REQUEST_SET_CONFIGURATION;
    setup.value := x"0001";
    setup.length := x"0000";

    ls_control_write(host_c, host_s, addr1_c, setup, ok);
    assert ok
      report "SET_CONFIGURATION was not carried out"
      severity failure;

    log_info("* Interrupt endpoint with nothing to report");

    ls_interrupt_poll(host_c, host_s, addr1_c, ep1_c, rsp);
    assert not rsp.timeout and rsp.pid = PID_NAK
      report "Idle interrupt endpoint did not NAK"
      severity failure;

    log_info("* Interrupt endpoint with a report pending");

    report_data <= report_a_c;
    report_length <= 8;
    report_valid <= '1';
    wait for 10 * ls_bit_time_c;

    ls_interrupt_poll(host_c, host_s, addr1_c, ep1_c, rsp);
    assert not rsp.timeout and rsp.pid = PID_DATA0
      report "First report is not a DATA0 packet"
      severity failure;
    assert rsp.crc_ok
      report "First report has a bad CRC16"
      severity failure;
    assert rsp.length = 8 and rsp.data(0 to 7) = report_a_c
      report "First report payload mismatch"
      severity failure;

    wait for 10 * ls_bit_time_c;
    assert consumed = 1
      report "Acknowledged report was not consumed"
      severity failure;

    report_valid <= '0';
    wait for 10 * ls_bit_time_c;

    ls_interrupt_poll(host_c, host_s, addr1_c, ep1_c, rsp);
    assert not rsp.timeout and rsp.pid = PID_NAK
      report "Drained interrupt endpoint did not NAK"
      severity failure;

    log_info("* Report retransmission after a corrupted CRC16");

    crc_corrupt <= '1';
    report_data <= report_b_c;
    report_length <= 8;
    report_valid <= '1';
    wait for 10 * ls_bit_time_c;

    ls_interrupt_poll(host_c, host_s, addr1_c, ep1_c, rsp);
    assert not rsp.timeout and rsp.pid = PID_DATA1
      report "Corrupted report is not a DATA1 packet"
      severity failure;
    assert not rsp.crc_ok
      report "Corrupted report passed the CRC16 check"
      severity failure;

    -- The poll left the packet unacknowledged, let the device time out
    -- waiting for a handshake.
    wait for 100 us;
    assert consumed = 1
      report "Unacknowledged report was consumed"
      severity failure;

    crc_corrupt <= '0';
    wait for 10 * ls_bit_time_c;

    ls_interrupt_poll(host_c, host_s, addr1_c, ep1_c, rsp);
    assert not rsp.timeout and rsp.pid = PID_DATA1
      report "Retransmitted report changed data toggle"
      severity failure;
    assert rsp.crc_ok
      report "Retransmitted report has a bad CRC16"
      severity failure;
    assert rsp.length = 8 and rsp.data(0 to 7) = report_b_c
      report "Retransmitted report payload mismatch"
      severity failure;

    wait for 10 * ls_bit_time_c;
    assert consumed = 2
      report "Retransmitted report was not consumed"
      severity failure;

    report_valid <= '0';
    wait for 10 * ls_bit_time_c;

    terminate(0);
  end process;

end architecture;
