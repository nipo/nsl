library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_usb, nsl_data;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_data.text.all;
use nsl_usb.usb.all;
use nsl_usb.descriptor.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_usb.testing.all;

entity tb is
end tb;

architecture sim of tb is

  signal rst_neg_ext   : std_logic;

  signal p2s: utmi8_p2s;
  signal s2p: utmi8_s2p;

  function byte_range(left, right: byte) return byte_string
  is
    variable ret : byte_string(to_integer(unsigned(left)) to to_integer(unsigned(right)));
  begin
    for i in ret'range
    loop
      ret(i) := byte(to_unsigned(i, 8));
    end loop;
    return ret;
  end function;

begin

  usb_hs_slave : entity work.dut
  port map(
    reset_n_i       => rst_neg_ext,

    utmi_data_o => s2p.data,
    utmi_data_i => p2s.data,
    utmi_system_o => s2p.system,
    utmi_system_i => p2s.system
  );

  stim: process
    constant prbs_buffer : byte_string := prbs_byte_string("000" & x"010", prbs15, 8192);
  begin
    utmi_init(s2p, p2s);
    utmi_reset(s2p, p2s);
    utmi_hs_handshake(s2p, p2s);
    utmi_sof(s2p, p2s, x"123");
    utmi_wait(s2p, p2s, 1 us);

    log_info("Testing Control address assignment");
    utmi_control_write(s2p, p2s,
                       dev_addr => x"00",
                       request => REQUEST_SET_ADDRESS,
                       value => x"24");

    log_info("Testing Decsriptor read with max length");
    log_info("* DUT should not answer more than 8 bytes");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_DESCRIPTOR,
                      length => x"08",
                      value => unsigned(DESCRIPTOR_TYPE_DEVICE) & x"00",
                      data => "1201000200000040");
    log_info("* DUT can answer more than 8 bytes");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_DESCRIPTOR,
                      length => x"40",
                      value => unsigned(DESCRIPTOR_TYPE_DEVICE) & x"00",
                      data => "120100020000004034127856000101020a01");

    log_info("Reading descriptor spanning more than 1 MPS");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_DESCRIPTOR,
                      length => x"200",
                      value => unsigned(DESCRIPTOR_TYPE_CONFIGURATION) & x"00",
                      data => "09022000010100804b0904000002ffffff000705810200020007050102000200",
                      mps => 64);

    log_info("Reading descriptor spanning exactly 1 MPS");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_DESCRIPTOR,
                      length => x"200",
                      value => unsigned(DESCRIPTOR_TYPE_STRING) & x"02",
                      blob => string_from_ascii("Some 64-byte long string descr."),
                      mps => 64);

    log_info("Reading dynamic string descriptor");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_DESCRIPTOR,
                      length => x"200",
                      value => unsigned(DESCRIPTOR_TYPE_STRING) & x"0a",
                      blob => string_from_ascii("1234"),
                      mps => 64);

    log_info("Testing Little IO");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "01",
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "02",
                      handshake_pid => PID_ACK);
    utmi_wait(s2p, p2s, 1 us);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "01",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "02",
                      handshake_pid => PID_ACK);

    log_info("Testing Bulk IO");
    log_info("* Bulk OUT toggle");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"00", x"3f")),
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"40", x"7f")),
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"80", x"bf")),
                      handshake_pid => PID_ACK);

    utmi_wait(s2p, p2s, 1 us);
    log_info("* Bulk IN retransmission");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"00", x"3f")),
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"40", x"7f")),
                      handshake_pid => PID_NAK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"40", x"7f")),
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"80", x"bf")),
                      handshake_pid => PID_ACK);
    
    log_info("* Bulk IN Empty NAK");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      error_pid => PID_NAK);

    log_info("* Bulk One-byte packet");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "aa",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "aa",
                      handshake_pid => PID_ACK);

    log_info("* Bulk Two-byte packet");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "bbcc",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "bbcc",
                      handshake_pid => PID_ACK);

    log_info("* Bulk three-byte packet");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "ffbbcc",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "ffbbcc",
                      handshake_pid => PID_ACK);

    log_info("Testing MPS NYET");
    log_info("* Feeding OUT ep until we reach NYET condition");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(0 to 511)),
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(512 to 1023)),
                      handshake_pid => PID_ACK);
    -- This one fits into the loopback fifo, but will be sent before flushing
    -- It flushes the first frame
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(1024 to 1030)),
                      handshake_pid => PID_NYET);

    utmi_wait(s2p, p2s, 10 us);
    -- This one will wait in the OUT endpoint
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(1030 to 1030+511)),
                      handshake_pid => PID_ACK);
    log_info("* Next should be a NYET");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(1030 + 512 to 1030 + 512 + 8)),
                      handshake_pid => PID_NYET);

    log_info("* buffer is not flushed yet, PING should NAK");
    utmi_transfer_ping(s2p, p2s,
                       dev_addr => x"24",
                       ep_no => x"1",
                       handshake_pid => PID_NAK);

    log_info("* Releasing first frame");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(0 to 511)),
                      handshake_pid => PID_ACK);

    log_info("* buffer is not flushed yet, PING should NAK");
    utmi_transfer_ping(s2p, p2s,
                       dev_addr => x"24",
                       ep_no => x"1",
                       handshake_pid => PID_NAK);

    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '1',
                     hex_data => to_hex_string(prbs_buffer(512 to 1023)),
                     handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '0',
                     hex_data => to_hex_string(prbs_buffer(1024 to 1030)),
                     handshake_pid => PID_ACK);

    utmi_wait(s2p, p2s, 10 us);

    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '1',
                     hex_data => to_hex_string(prbs_buffer(1030 to 1030+511)),
                     handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '0',
                     hex_data => to_hex_string(prbs_buffer(1030 + 512 to 1030 + 512 + 8)),
                     handshake_pid => PID_ACK);

    log_info("* Bulk aligned packet");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(0 to 511)),
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_NYET);
    utmi_wait(s2p, p2s, 10 us);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(0 to 511)),
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      error_pid => PID_NAK);


    log_info("* Bulk aligned packet2");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(512 to 1023)),
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(1024 to 1024+511)),
                      handshake_pid => PID_ACK);
    utmi_wait(s2p, p2s, 10 us);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "",
                      handshake_pid => PID_ACK);

    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(512 to 1023)),
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(1024 to 1024+511)),
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "",
                      handshake_pid => PID_ACK);


    log_info("* Bulk One-byte packet");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "aa",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "aa",
                      handshake_pid => PID_ACK);
    

    log_info("* Bulk ZLP out (should drop)");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "",
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "",
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_ACK);

    log_info("* Bulk One-byte packet");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "aa",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "aa",
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "bb",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "bb",
                      handshake_pid => PID_ACK);
    
    log_info("* Halting OUT endpoint");
    utmi_control_write(s2p, p2s,
                       dev_addr => x"24",
                       request => REQUEST_SET_FEATURE,
                       recipient => SETUP_RECIPIENT_ENDPOINT,
                       value => feature_selector_to_value(FEATURE_SELECTOR_ENDPOINT_HALT),
                       index => endpoint_index(HOST_TO_DEVICE, 1));

    log_info("* Should get a STALL");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(0 to 31)),
                      handshake_pid => PID_STALL);

    log_info("* Resetting OUT endpoint");
    utmi_control_write(s2p, p2s,
                       dev_addr => x"24",
                       request => REQUEST_CLEAR_FEATURE,
                       recipient => SETUP_RECIPIENT_ENDPOINT,
                       value => feature_selector_to_value(FEATURE_SELECTOR_ENDPOINT_HALT),
                       index => endpoint_index(HOST_TO_DEVICE, 1));

    log_info("* Toggle got reset, this transfer should be ACKed but ignored");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(0 to 31)),
                      handshake_pid => PID_ACK);

    utmi_wait(s2p, p2s, 10 us);
    log_info("* As no data is expected to have flown through, this should NAK");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     error_pid => PID_NAK);

    log_info("* This one should go through");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(32 to 63)),
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '1',
                     hex_data => to_hex_string(prbs_buffer(32 to 63)),
                     handshake_pid => PID_ACK);
    
    log_info("Control get device status");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_STATUS,
                      data => "0000");

    log_info("Control get configuration (=0)");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_CONFIGURATION,
                      data => "00");

    log_info("Control set configuration =1");
    utmi_control_write(s2p, p2s,
                       dev_addr => x"24",
                       request => REQUEST_SET_CONFIGURATION,
                       value => x"1");

    log_info("Control get configuration (=1)");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_CONFIGURATION,
                      data => "01");

    terminate(0);
  end process;
  
end sim;
