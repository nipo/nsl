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
-- attached full-/low-speed device, record its identity, then poll its
-- interrupt IN endpoint forever.
--
-- The program only ever addresses one device at address 1 on endpoint
-- 1, which is what boot-protocol keyboards, mice and the vast
-- majority of HID gamepads expose.
--
-- Control reads use bMaxPacketSize0 and descriptor-relative offsets,
-- validate CRCs, retry NAKs, and complete their OUT status stage.
-- IN data toggles are not checked.
package hid_program is

  type hid_program_config_t is
  record
    poll_interval_ms: natural;
    -- 1 to 8, sizes the IN sample timeout
    report_length: natural;
    -- for SET_CONFIGURATION
    configuration_value: natural;
    -- Milliseconds to let a newly plugged device's contacts settle
    -- before talking to it.  Shortening it is for tests, which would
    -- otherwise spend most of their run waiting.
    debounce_ms: natural;
  end record;

  constant hid_program_defaults_c: hid_program_config_t := (
    poll_interval_ms => 8,
    report_length => 8,
    configuration_value => 1,
    debounce_ms => 200);

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

  -- Read the device descriptor and the first configuration's prefix.
  -- A short packet terminates a descriptor shorter than the request.
  constant device_read_length_c: natural := 18;
  constant configuration_read_length_c: natural := 64;

  constant lbl_start_c: label_t := 0;
  constant lbl_poll_wait_c: label_t := 1;
  constant lbl_debounce_c: label_t := 2;
  constant lbl_connected_c: label_t := 3;
  constant lbl_disconnected_c: label_t := 4;
  constant lbl_device_desc_lo_c: label_t := 5;
  constant lbl_config_desc_0_c: label_t := 7;
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
  constant lbl_poll_sof_c: label_t := 20;
  constant lbl_poll_ka_done_c: label_t := 21;
  constant lbl_recovery_sof_c: label_t := 22;
  constant lbl_recovery_ka_done_c: label_t := 23;
  constant lbl_device_sof_c: label_t := 25;
  constant lbl_device_ka_done_c: label_t := 26;
  constant lbl_config_sof_c: label_t := 27;
  constant lbl_config_ka_done_c: label_t := 28;

  -- Two bit times of single-ended zero followed by idle J.  On
  -- low speed, J is D+ low and D- high.  This is both the end of
  -- packet marker and, standalone, the low-speed keep-alive.
  function eop return program_t
  is
  begin
    return out4(dp => "0000", dm => "0011");
  end function;

  -- A millisecond's worth of bus activity, whichever speed the device
  -- turned out to be: a start-of-frame token at full speed, a bare
  -- end of packet at low speed.  Either keeps a device from deciding
  -- the bus has gone quiet and suspending itself.
  --
  -- Only the full-speed one carries a frame number, and the engine
  -- rather than the program counts it: a token whose contents change
  -- every millisecond cannot be a constant assembled here, which is
  -- the whole reason SOF is an instruction.
  --
  -- The two labels are scratch and must not be used elsewhere.
  function keepalive(fs_label, done_label: label_t) return program_t
  is
  begin
    return bfs(fs_label)
      & eop
      & hiz
      & jmp(done_label)

      & lbl(fs_label)
      & out_bytes(sync_c & pid_byte(PID_SOF))
      & sof(0)
      & sof(1)
      & eop
      & hiz

      & lbl(done_label);
  end function;

  -- Sync, PID, address and endpoint with its CRC5.
  function token_packet(pid: pid_t;
                        addr: device_address_t;
                        endp: endpoint_no_t) return program_t
  is
  begin
    return out_bytes(sync_c & pid_byte(pid) & token_data(addr, endp)) & eop;
  end function;

  -- Sync, data PID, payload and its CRC16.
  function data_packet(payload: byte_string; pid: pid_t := PID_DATA0) return program_t
  is
    constant state: crc_state_t := crc_update(data_crc_params_c,
                                              crc_init(data_crc_params_c),
                                              payload);
  begin
    return out_bytes(sync_c & pid_byte(pid)
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
      & data_packet(setup_pack(request));
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
    assert samples < 2048
      report "Receive timeout does not fit in W"
      severity failure;
    return samples;
  end function;

  -- Includes a maximum-size full-speed control packet.
  constant descriptor_timeout_c: natural
    := receive_timeout(control_length_max_c);

  function control_status return program_t is
  begin
    return token_packet(PID_OUT, default_address_c, control_endpoint_c)
      & data_packet(null_byte_string, PID_DATA1)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_start_c)
      & berr(lbl_start_c);
  end function;

  -- ACK before extracting fields so software work cannot extend the
  -- full-speed handshake turnaround. NAK and CRC errors retry the
  -- same packet without advancing the descriptor offset.
  function control_stage(saves: program_t; retry: label_t) return program_t
  is
  begin
    return call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(retry)
      & berr(retry)
      & call(lbl_ack_c)
      & hiz
      & saves
      & bmore(retry);
  end function;

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
    assert cfg.debounce_ms >= 1 and cfg.debounce_ms <= 255
      report "HID debounce must be in 1 to 255 ms"
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

      -- Which line a device pulls up is both how it says it is there
      -- and how it says how fast it runs, so the two questions are
      -- one and are answered here: after this the line the device
      -- pulled up is the one BZ tests, whichever it was.
      --
      -- Only on this path.  The bus is idle here, and a speed read
      -- off a bus carrying traffic would be no speed at all.
      & speed_sense
      & bz(lbl_start_c)

      -- A device pulls its line up as soon as it is plugged; let the
      -- contacts settle before talking to it.
      & ldi(cfg.debounce_ms)
      & lbl(lbl_debounce_c)
      & wait_frame
      & djnz(lbl_debounce_c)

      -- Read again now the contacts have stopped moving: what was
      -- latched above was enough to notice the device, but a bouncing
      -- line is a poor thing to have decided a bit rate from.
      & speed_sense

      & call(lbl_reset_c)

      -- bMaxPacketSize0 is in the first eight bytes, so it is known
      -- before deciding whether a subsequent IN transaction is due.
      & control_read(device_read_length_c)
      & setup_txn(default_address_c,
                  get_descriptor(DESCRIPTOR_TYPE_DEVICE,
                                 device_read_length_c))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_start_c)
      & berr(lbl_start_c)

      & lbl(lbl_device_desc_lo_c)
      & wait_frame
      & keepalive(lbl_device_sof_c, lbl_device_ka_done_c)
      & control_stage(save(save_reg_ep0_mps_c, 7)
                      & save(save_reg_vid_l_c, 8)
                      & save(save_reg_vid_h_c, 9)
                      & save(save_reg_pid_l_c, 10)
                      & save(save_reg_pid_h_c, 11),
                      lbl_device_desc_lo_c)

      & control_status

      -- The first interface follows the nine-byte configuration
      -- header. SAVE uses descriptor offsets regardless of EP0 MPS.
      & control_read(configuration_read_length_c)
      & setup_txn(default_address_c,
                  get_descriptor(DESCRIPTOR_TYPE_CONFIGURATION,
                                 configuration_read_length_c))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_start_c)
      & berr(lbl_start_c)

      & lbl(lbl_config_desc_0_c)
      & wait_frame
      & keepalive(lbl_config_sof_c, lbl_config_ka_done_c)
      & control_stage(save(save_reg_if_class_c, 14)
                      & save(save_reg_if_subclass_c, 15)
                      & save(save_reg_if_protocol_c, 16),
                      lbl_config_desc_0_c)

      & control_status

      -- SET_ADDRESS, still at the default address.  Its status stage
      -- is a zero-length IN, and the device only starts answering on
      -- the new address once that status stage completed.
      & setup_txn(default_address_c, set_address(device_address_c))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_start_c)
      & berr(lbl_start_c)

      & lbl(lbl_set_address_status_c)
      & call(lbl_control_in_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_set_address_status_c)
      & berr(lbl_set_address_status_c)
      & call(lbl_ack_c)
      & hiz
      -- SET_ADDRESS recovery is at least 2ms, even when the first
      -- free-running millisecond tick is immediately due.
      & wait_frame
      & wait_frame
      & wait_frame

      -- SET_CONFIGURATION at the assigned address.
      & setup_txn(device_address_c, set_configuration(cfg.configuration_value))
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_start_c)
      & berr(lbl_start_c)

      & lbl(lbl_set_config_status_c)
      & token_packet(PID_IN, device_address_c, control_endpoint_c)
      & hiz
      & ldi(descriptor_timeout_c)
      & call(lbl_receive_c)
      & bnak(lbl_set_config_status_c)
      & berr(lbl_set_config_status_c)
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
      & keepalive(lbl_poll_sof_c, lbl_poll_ka_done_c)
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

      -- At least 10ms of SE0, including an initial partial tick.
      -- Then 40ms of recovery with keep-alives to hold the device awake.
      & lbl(lbl_reset_c)
      & out0
      & ldi(11)
      & lbl(lbl_reset_se0_c)
      & wait_frame
      & djnz(lbl_reset_se0_c)
      & hiz
      & ldi(40)
      & lbl(lbl_reset_recovery_c)
      & wait_frame
      & keepalive(lbl_recovery_sof_c, lbl_recovery_ka_done_c)
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
