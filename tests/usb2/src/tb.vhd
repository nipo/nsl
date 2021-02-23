library work, ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.usb_commands.all;

library nsl_simulation, nsl_usb, nsl_data;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_data.text.all;
use nsl_usb.usb.all;
use nsl_usb.descriptor.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.prbs.all;

entity tb is
end tb;

architecture sim of tb is

  signal rst_neg_ext   : std_logic;

  signal p2s: utmi8_p2s;
  signal s2p: utmi8_s2p;

  signal s_flush : std_ulogic;

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
    utmi_system_i => p2s.system,

    flush_i => s_flush
  );

  stim: process
    constant prbs_buffer : byte_string := prbs_byte_string("000" & x"010", prbs15, 8192);
  begin
    s_flush <= '0';
    
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
                      data => "09024b0002010080fa080b000202020000090400000102020000052400200104240200052406000105240100010705820308000f09040100020a000000070581"
                      &"0200020007050102000200",
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
    utmi_transfer_in(s2p, p2s,
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
    log_info("* Bulk IN merged");
    log_info("* Bulk IN retransmission");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"00", x"bf")),
                      handshake_pid => PID_NAK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"00", x"bf")),
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

    s_flush <= '1';
    log_info("Testing IN flush / ZLP");
    log_info("* Force flush set to 1 in IN endpoint, should get ZLPs");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "",
                      handshake_pid => PID_ACK);

    log_info("* Testing ZLP retransmission");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_NAK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "",
                      handshake_pid => PID_ACK);

    s_flush <= '0';
    log_info("* Force flush back to normal, this is the last expected ZLP");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => "",
                      handshake_pid => PID_ACK);

    log_info("Testing IN failed transfer reemission");
    log_info("* Filling IN buffer with some data");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"c0", x"df")),
                      handshake_pid => PID_ACK);

    log_info("* Failing an IN transfer");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"c0", x"df")),
                      handshake_pid => PID_NAK);

    log_info("* Filling IN buffer with more data");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"e0", x"ff")),
                      handshake_pid => PID_ACK);

    -- Here, packet must not include e0-ff
    log_info("* Reemitted transfer must not include more data");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"c0", x"df")),
                      handshake_pid => PID_ACK);

    log_info("* Adding even more data");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(byte_range(x"00", x"1f")),
                      handshake_pid => PID_ACK);

    utmi_wait(s2p, p2s, 1 us);
    -- But here, it should contain e0->1f
    log_info("* Transfer can merge the two last OUTs");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"e0", x"ff") & byte_range(x"00", x"1f")),
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

    log_info("* buffer is not full yet, PING should ACK");
    utmi_transfer_ping(s2p, p2s,
                       dev_addr => x"24",
                       ep_no => x"1",
                       handshake_pid => PID_ACK);

    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(1024 to 1535)),
                      handshake_pid => PID_ACK);

    log_info("* Next should be a NYET");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(1536 to 2047)),
                      handshake_pid => PID_NYET);

    log_info("* While we are here, just test a PING");
    utmi_transfer_ping(s2p, p2s,
                       dev_addr => x"24",
                       ep_no => x"1",
                       handshake_pid => PID_NAK);

    log_info("* No more room, should get a NAK");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(2048 to 2559)),
                      handshake_pid => PID_NAK);

    log_info("* Releasing some space");
    utmi_transfer_in(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => to_hex_string(prbs_buffer(0 to 511)),
                      handshake_pid => PID_ACK);

    log_info("* We are too soon after releasing space, PING should still NAK");
    utmi_transfer_ping(s2p, p2s,
                       dev_addr => x"24",
                       ep_no => x"1",
                       handshake_pid => PID_NAK);
    
    utmi_wait(s2p, p2s, 10 us);

    log_info("* Now, data left the OUT endpoint buffer, PING should ACK");
    utmi_transfer_ping(s2p, p2s,
                       dev_addr => x"24",
                       ep_no => x"1",
                       handshake_pid => PID_ACK);

    -- We filled 2048 bytes, popped 512, DUT has 1024 bytes of input
    -- buffer, 1024 of output buffer, and 16 bytes of loopback fifo =>
    -- there are 512+16 free bytes, just more than one MPS.
    log_info("* There should be ~528 bytes left in OUT buffer");
    
    log_info("* Should end IN NYET");
    -- Resend of transfer above
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(prbs_buffer(2048 to 2559)),
                      handshake_pid => PID_NYET);

    log_info("* Flush nearly all");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '0',
                     hex_data => to_hex_string(prbs_buffer(512 to 1023)),
                     handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '1',
                     hex_data => to_hex_string(prbs_buffer(1024 to 1535)),
                     handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '0',
                     hex_data => to_hex_string(prbs_buffer(1536 to 2047)),
                     handshake_pid => PID_ACK);

    log_info("* This IN read spans exactly one MPS");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '1',
                     hex_data => to_hex_string(prbs_buffer(2048 to 2559)),
                     handshake_pid => PID_ACK);

    log_info("* Next should be a ZLP");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '0',
                     hex_data => "",
                     handshake_pid => PID_ACK);

    log_info("* Should get a NAK");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     error_pid => PID_NAK);

    log_info("Testing EP halting");
    log_info("* Halting IN endpoint");
    utmi_control_write(s2p, p2s,
                       dev_addr => x"24",
                       request => REQUEST_SET_FEATURE,
                       recipient => SETUP_RECIPIENT_ENDPOINT,
                       value => feature_selector_to_value(FEATURE_SELECTOR_ENDPOINT_HALT),
                       index => endpoint_index(DEVICE_TO_HOST, 1));

    log_info("* Should get a STALL");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     error_pid => PID_STALL);

    log_info("* Resetting IN endpoint");
    utmi_control_write(s2p, p2s,
                       dev_addr => x"24",
                       request => REQUEST_CLEAR_FEATURE,
                       recipient => SETUP_RECIPIENT_ENDPOINT,
                       value => feature_selector_to_value(FEATURE_SELECTOR_ENDPOINT_HALT),
                       index => endpoint_index(DEVICE_TO_HOST, 1));

    log_info("* Should get a NAK");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     error_pid => PID_NAK);

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
                     toggle => '0',
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
