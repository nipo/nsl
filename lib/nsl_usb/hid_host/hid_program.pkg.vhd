library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_usb;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_usb.usb.all;
use nsl_usb.ukp.all;
use nsl_usb.hid_host.all;

-- Microcode program driving hid_host_engine: enumerate the single
-- attached low-speed device, record its identity, then poll its
-- interrupt IN endpoint forever.
--
-- The program only ever addresses one device at address 1 on endpoint
-- 1, which is what boot-protocol keyboards, mice and the vast
-- majority of HID gamepads expose.
--
-- Control transfers here follow the minimal sequence a HID device
-- accepts: SETUP with a DATA0 payload, then IN transactions ACKed
-- unconditionally.  Data toggles of the IN data stage are neither
-- driven nor verified, and the status stage of the two
-- GET_DESCRIPTOR transfers is skipped: a bus reset follows each of
-- them and clears whatever endpoint state was left behind.
package hid_program is

  type hid_program_config_t is
  record
    poll_interval_ms: natural;
    -- 1 to 8, sizes the IN sample timeout
    report_length: natural;
    -- for SET_CONFIGURATION
    configuration_value: natural;
  end record;

  constant hid_program_defaults_c: hid_program_config_t := (
    poll_interval_ms => 8,
    report_length => 8,
    configuration_value => 1);

  function hid_program(cfg: hid_program_config_t) return program_t;

end package;

package body hid_program is

  constant sync_c: byte_string := from_hex("80");

  -- Address 0 is the default address every device answers to before
  -- SET_ADDRESS; address 1 is the one this program assigns.
  constant default_address_c: device_address_t := to_unsigned(0, 7);
  constant device_address_c: device_address_t := to_unsigned(1, 7);
  constant control_endpoint_c: endpoint_no_t := x"0";
  constant interrupt_endpoint_c: endpoint_no_t := x"1";

  -- Descriptor sizes requested from the device.  18 is the whole
  -- device descriptor; 24 spans the 9-byte configuration descriptor
  -- plus enough of the first interface descriptor to reach
  -- bInterfaceProtocol.
  constant device_descriptor_length_c: natural := 18;
  constant configuration_descriptor_length_c: natural := 24;

  constant lbl_start_c: label_t := 0;
  constant lbl_poll_wait_c: label_t := 1;
  constant lbl_debounce_c: label_t := 2;
  constant lbl_connected_c: label_t := 3;
  constant lbl_disconnected_c: label_t := 4;
  constant lbl_device_desc_lo_c: label_t := 5;
  constant lbl_device_desc_hi_c: label_t := 6;
  constant lbl_config_desc_0_c: label_t := 7;
  constant lbl_config_desc_1_c: label_t := 8;
  constant lbl_config_desc_2_c: label_t := 9;
  constant lbl_set_address_status_c: label_t := 10;
  constant lbl_set_config_status_c: label_t := 11;
  constant lbl_reset_c: label_t := 12;
  constant lbl_reset_se0_c: label_t := 13;
  constant lbl_reset_recovery_c: label_t := 14;
  constant lbl_receive_c: label_t := 15;
  constant lbl_receive_idle_c: label_t := 16;
  constant lbl_receive_settle_c: label_t := 17;
  constant lbl_ack_c: label_t := 18;
  constant lbl_control_in_c: label_t := 19;

  -- Two bit times of single-ended zero followed by idle J.  On
  -- low speed, J is D+ low and D- high.  This is both the end of
  -- packet marker and, standalone, the low-speed keep-alive.
  function eop return program_t
  is
  begin
    return out4(dp => "0000", dm => "0011");
  end function;

  -- Sync, PID, address and endpoint with its CRC5.
  function token_packet(pid: pid_t;
                        addr: device_address_t;
                        endp: endpoint_no_t) return program_t
  is
  begin
    return out_bytes(sync_c & pid_byte(pid) & token_data(addr, endp)) & eop;
  end function;

  -- Sync, DATA0 PID, payload and its CRC16.
  function data0_packet(payload: byte_string) return program_t
  is
    constant state: crc_state_t := crc_update(data_crc_params_c,
                                              crc_init(data_crc_params_c),
                                              payload);
  begin
    return out_bytes(sync_c & pid_byte(PID_DATA0)
                     & payload & crc_spill(data_crc_params_c, state))
      & eop;
  end function;

  -- SETUP token immediately followed by its data stage, both to the
  -- control endpoint.  The bus is left driven; callers issue HIZ once
  -- the device may answer.
  function setup_txn(addr: device_address_t;
                     request: setup_t) return program_t
  is
  begin
    return token_packet(PID_SETUP, addr, control_endpoint_c)
      & data0_packet(setup_pack(request));
  end function;

  -- Number of bit samples IN may take before giving up on a device
  -- answer.  A DATA packet carrying payload_bytes occupies a PID, the
  -- payload and a CRC16 on the wire; bit stuffing inserts at most one
  -- bit every six, and the device takes a few bit times to turn the
  -- bus around.
  function receive_timeout(payload_bytes: natural) return natural
  is
    constant wire_bits: natural := (payload_bytes + 3) * 8;
    constant samples: natural := wire_bits + (wire_bits / 5) + 8;
  begin
    assert samples < 256
      report "Receive timeout does not fit in W"
      severity failure;
    return samples;
  end function;

  -- Every descriptor packet of the enumeration sequence is a full
  -- low-speed maximum-size packet.
  constant descriptor_timeout_c: natural := receive_timeout(8);

  function get_descriptor(descriptor_type: descriptor_type_t;
                          length: natural) return setup_t
  is
  begin
    return setup_t'(direction => DEVICE_TO_HOST,
                    rtype => SETUP_TYPE_STANDARD,
                    recipient => SETUP_RECIPIENT_DEVICE,
                    request => REQUEST_GET_DESCRIPTOR,
                    value => unsigned(descriptor_type) & to_unsigned(0, 8),
                    index => x"0000",
                    length => to_unsigned(length, 16));
  end function;

  function set_address(addr: device_address_t) return setup_t
  is
  begin
    return setup_t'(direction => HOST_TO_DEVICE,
                    rtype => SETUP_TYPE_STANDARD,
                    recipient => SETUP_RECIPIENT_DEVICE,
                    request => REQUEST_SET_ADDRESS,
                    value => resize(addr, 16),
                    index => x"0000",
                    length => x"0000");
  end function;

  function set_configuration(value: natural) return setup_t
  is
  begin
    return setup_t'(direction => HOST_TO_DEVICE,
                    rtype => SETUP_TYPE_STANDARD,
                    recipient => SETUP_RECIPIENT_DEVICE,
                    request => REQUEST_SET_CONFIGURATION,
                    value => to_unsigned(value, 16),
                    index => x"0000",
                    length => x"0000");
  end function;

  function hid_program(cfg: hid_program_config_t) return program_t
  is
    constant report_timeout_c: natural := receive_timeout(cfg.report_length);
  begin
    assert cfg.report_length >= 1 and cfg.report_length <= report_length_max_c
      report "HID report length must be in 1 to "
      & integer'image(report_length_max_c)
      severity failure;
    assert cfg.poll_interval_ms >= 1 and cfg.poll_interval_ms <= 255
      report "HID poll interval must be in 1 to 255 ms"
      severity failure;
    assert cfg.configuration_value >= 1 and cfg.configuration_value <= 255
      report "Configuration value must be in 1 to 255"
      severity failure;

    return
      -- Idle: one millisecond tick at a time, either servicing an
      -- enumerated device or waiting for one to show up.  W paces the
      -- interrupt endpoint polling.
      lbl(lbl_start_c)
      & ldi(cfg.poll_interval_ms)
      & lbl(lbl_poll_wait_c)
      & wait_frame
      & bc(lbl_connected_c)
      & bz(lbl_start_c)

      -- A device pulls D- up as soon as it is plugged; let the
      -- contacts settle before talking to it.
      & ldi(200)
      & lbl(lbl_debounce_c)
      & wait_frame
      & djnz(lbl_debounce_c)

      & call(lbl_reset_c)

      -- GET_DESCRIPTOR(device) at the default address.  The answer
      -- comes as 8-byte packets; the second one carries descriptor
      -- bytes 8 to 15, and idVendor starts at descriptor offset 8, so
      -- vendor and product ids are receive buffer bytes 0 to 3.
      & setup_txn(default_address_c,
                  get_descriptor(DESCRIPTOR_TYPE_DEVICE,
                                 device_descriptor_length_c))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)

      & lbl(lbl_device_desc_lo_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_device_desc_lo_c)
      & call(lbl_ack_c)
      & hiz

      & lbl(lbl_device_desc_hi_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_device_desc_hi_c)
      & save(save_reg_vid_l_c, 0)
      & save(save_reg_vid_h_c, 1)
      & save(save_reg_pid_l_c, 2)
      & save(save_reg_pid_h_c, 3)
      & call(lbl_ack_c)
      & hiz

      -- No status stage was run for the transfer above; the reset
      -- puts the device back to a known state.
      & call(lbl_reset_c)

      -- GET_DESCRIPTOR(configuration) at the default address.  The
      -- 9-byte configuration descriptor is immediately followed by
      -- the 9-byte interface descriptor of interface 0, whose
      -- bInterfaceClass, bInterfaceSubClass and bInterfaceProtocol
      -- are at descriptor offsets 14, 15 and 16.  With 8-byte
      -- packets, offsets 14 and 15 are bytes 6 and 7 of the second
      -- packet, and offset 16 is byte 0 of the third.
      & setup_txn(default_address_c,
                  get_descriptor(DESCRIPTOR_TYPE_CONFIGURATION,
                                 configuration_descriptor_length_c))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)

      & lbl(lbl_config_desc_0_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_config_desc_0_c)
      & call(lbl_ack_c)
      & hiz

      & lbl(lbl_config_desc_1_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_config_desc_1_c)
      & save(save_reg_if_class_c, 6)
      & save(save_reg_if_subclass_c, 7)
      & call(lbl_ack_c)
      & hiz

      & lbl(lbl_config_desc_2_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_config_desc_2_c)
      & save(save_reg_if_protocol_c, 0)
      & call(lbl_ack_c)
      & hiz

      & call(lbl_reset_c)

      -- SET_ADDRESS, still at the default address.  Its status stage
      -- is a zero-length IN, and the device only starts answering on
      -- the new address once that status stage completed.
      & setup_txn(default_address_c, set_address(device_address_c))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)

      & lbl(lbl_set_address_status_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_set_address_status_c)
      & call(lbl_ack_c)
      & hiz
      & wait_frame

      -- SET_CONFIGURATION at the assigned address.
      & setup_txn(device_address_c, set_configuration(cfg.configuration_value))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)

      & lbl(lbl_set_config_status_c)
      & token_packet(PID_IN, device_address_c, control_endpoint_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_set_config_status_c)
      & call(lbl_ack_c)
      & hiz

      -- Identity registers are all written and the device is
      -- configured: publish it.  C is toggled here and on disconnect
      -- only.
      & toggle
      & jmp(lbl_start_c)

      -- Enumerated device, one millisecond into the poll interval.
      & lbl(lbl_connected_c)
      & bz(lbl_disconnected_c)
      & eop
      & hiz
      & djnz(lbl_poll_wait_c)

      -- Interval elapsed: one interrupt IN transaction.  A NAK means
      -- the device has nothing to report, a CRC error means the
      -- report was corrupted; both are retried at the next interval,
      -- and withholding the ACK on error makes the device resend.
      & token_packet(PID_IN, device_address_c, interrupt_endpoint_c)
      & hiz
      & ldi(report_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_start_c)
      & berr(lbl_start_c)
      & call(lbl_ack_c)
      & hiz
      & jmp(lbl_start_c)

      & lbl(lbl_disconnected_c)
      & toggle
      & jmp(lbl_start_c)

      -- Bus reset: 10ms of single-ended zero, then 40ms of recovery
      -- during which keep-alives hold the device awake.
      & lbl(lbl_reset_c)
      & out0
      & ldi(10)
      & lbl(lbl_reset_se0_c)
      & wait_frame
      & djnz(lbl_reset_se0_c)
      & hiz
      & ldi(40)
      & lbl(lbl_reset_recovery_c)
      & wait_frame
      & eop
      & hiz
      & djnz(lbl_reset_recovery_c)
      & wait_frame
      & ret

      -- Receive one packet, W preloaded with the sample timeout, then
      -- wait for the bus to settle back to idle J before the caller
      -- drives it again.
      & lbl(lbl_receive_c)
      & start
      & usb_in
      & lbl(lbl_receive_idle_c)
      & ldi(2)
      & lbl(lbl_receive_settle_c)
      & bz(lbl_receive_idle_c)
      & djnz(lbl_receive_settle_c)
      & ret

      & lbl(lbl_control_in_c)
      & token_packet(PID_IN, default_address_c, control_endpoint_c)
      & ret

      & lbl(lbl_ack_c)
      & out_bytes(sync_c & pid_byte(PID_ACK))
      & eop
      & ret;
  end function;

end package body;
