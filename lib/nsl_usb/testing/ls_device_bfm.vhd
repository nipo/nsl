library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_simulation;
use nsl_usb.usb.all;
use nsl_usb.io.all;
use nsl_usb.ls_bfm.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

-- Behavioral low-speed USB device, wire-level on D+/D-.  It models the
-- shared medium as well, so a host core may be attached directly
-- through its usb_io_c/usb_io_s pair.
entity ls_device_bfm is
  generic(
    device_descriptor_c: nsl_data.bytestream.byte_string;
    config_descriptor_c: nsl_data.bytestream.byte_string;
    interrupt_ep_c: natural := 1
    );
  port(
    -- Wire-level connection, seen from the host core: host_i is what
    -- the host drives, host_o is what the host reads back.  The BFM
    -- models the shared medium and the device pull-up on D-.
    host_i: in nsl_usb.io.usb_io_c;
    host_o: out nsl_usb.io.usb_io_s;

    present_i: in std_ulogic := '1';

    -- Interrupt IN endpoint source.  When valid is high, the next IN
    -- token on interrupt_ep_c gets a DATA packet with
    -- report_data_i(0 to report_length_i - 1); the entry is consumed
    -- (ready_o pulse) only once the host ACKs.  When valid is low the
    -- endpoint NAKs.
    report_data_i: in nsl_data.bytestream.byte_string(0 to 7) := (others => x"00");
    report_length_i: in natural range 0 to 8 := 0;
    report_valid_i: in std_ulogic := '0';
    report_ready_o: out std_ulogic;

    -- While high, report data packets are sent with corrupted CRC16.
    crc_corrupt_i: in std_ulogic := '0'
    );
end entity;

architecture beh of ls_device_bfm is

  constant ctx_c: log_context := "ls-device";

  constant dev_desc_c: byte_string(0 to device_descriptor_c'length-1) := device_descriptor_c;
  constant cfg_desc_c: byte_string(0 to config_descriptor_c'length-1) := config_descriptor_c;

  constant ep0_mps_c: natural := 8;

  -- A bus reset is a much shorter SE0 than this, but a low-speed host
  -- also emits bare EOPs as keep-alives.  Anything longer than a
  -- handful of bit times can only be a reset.
  constant reset_min_c: time := 100 us;

  constant response_timeout_c: time := 16 * ls_bit_time_c;

  signal medium_dp, medium_dm: std_ulogic;
  signal medium: usb_io_s;

  -- Device side of the shared medium.  This reuses the host-side
  -- record so that the transmit helpers are shared; dp_pullup_en has no
  -- meaning here, the pull-up is modelled by present_i.
  signal device_drive: usb_io_c := (dp => '0', dm => '0',
                                    oe => '0', dp_pullup_en => '0');

begin

  medium_dp <= host_i.dp when host_i.oe = '1'
               else device_drive.dp when device_drive.oe = '1'
               else '0';

  medium_dm <= host_i.dm when host_i.oe = '1'
               else device_drive.dm when device_drive.oe = '1'
               else present_i;

  medium <= usb_io_s'(dp => medium_dp, dm => medium_dm);
  host_o <= medium;

  contention: process(host_i.oe, device_drive.oe) is
  begin
    if host_i.oe = '1' and device_drive.oe = '1' then
      log_error(ctx_c, "Host and device drive the bus at the same time");
    end if;
  end process;

  device: process is
    variable dev_addr: device_address_t := (others => '0');
    variable new_addr: device_address_t := (others => '0');
    variable addr_pending: boolean := false;
    variable configured: boolean := false;
    variable setup: setup_t;
    variable ctrl_buf: byte_string(0 to 255) := (others => x"00");
    variable ctrl_len: natural := 0;
    variable ctrl_off: natural := 0;
    variable ctrl_toggle: std_ulogic := '1';
    variable ctrl_stall: boolean := false;
    variable ep_toggle: std_ulogic := '0';
    variable rx: byte_string(0 to 71);
    variable rx_len: natural := 0;
    variable tok_addr: device_address_t;
    variable tok_ep: endpoint_no_t;
    variable ep_v: std_ulogic_vector(3 downto 0);
    variable pid: pid_t;
    variable chunk: natural;
    variable dtype: descriptor_type_t;

    procedure rx_wait(variable data: out byte_string;
                      variable length: out natural;
                      timeout: time)
    is
    begin
      length := 0;
      wait until medium.dp = '1' for timeout;
      if medium.dp /= '1' then
        return;
      end if;
      ls_packet_decode(medium, data, length);
    end procedure;

    function is_ack(packet: byte_string; length: natural) return boolean
    is
    begin
      return length = 1
        and pid_byte_is_correct(packet(packet'low))
        and pid_get(packet(packet'low)) = PID_ACK;
    end function;

    procedure state_reset
    is
    begin
      dev_addr := (others => '0');
      new_addr := (others => '0');
      addr_pending := false;
      configured := false;
      ctrl_stall := false;
      ctrl_len := 0;
      ctrl_off := 0;
      ctrl_toggle := '1';
      ep_toggle := '0';
    end procedure;

  begin
    report_ready_o <= '0';
    device_drive.oe <= '0';
    device_drive.dp <= '0';
    device_drive.dm <= '0';
    device_drive.dp_pullup_en <= '0';

    loop
      if present_i /= '1' then
        wait until present_i = '1';
      end if;

      if medium.dm = '1' then
        wait until medium.dm = '0';
      end if;

      if medium.dp /= '1' then
        -- SE0: either a keep-alive EOP, which just goes by, or a bus
        -- reset.
        wait until medium.dm = '1' for reset_min_c;
        if medium.dm = '0' then
          log_info(ctx_c, "Bus reset");
          state_reset;
          wait until medium.dm = '1';
        end if;
        next;
      end if;

      ls_packet_decode(medium, rx, rx_len);

      next when rx_len = 0;

      if not pid_byte_is_correct(rx(0)) then
        log_warning(ctx_c, "Malformed PID byte " & to_hex_string(rx(0)));
        next;
      end if;

      pid := pid_get(rx(0));

      if pid /= PID_SETUP and pid /= PID_IN and pid /= PID_OUT then
        log_debug(ctx_c, "Ignoring packet with PID " & to_hex_string(rx(0)));
        next;
      end if;

      if rx_len /= 3 then
        log_warning(ctx_c, "Token packet has " & to_string(rx_len) & " bytes");
        next;
      end if;

      tok_addr := unsigned(rx(1)(6 downto 0));
      ep_v(0) := rx(1)(7);
      ep_v(3 downto 1) := rx(2)(2 downto 0);
      tok_ep := unsigned(ep_v);

      if rx(1 to 2) /= token_data(tok_addr, tok_ep) then
        log_warning(ctx_c, "Token CRC5 mismatch");
        next;
      end if;

      next when tok_addr /= dev_addr;

      log_info(ctx_c, "Token " & to_hex_string(rx(0))
               & " for endpoint " & to_string(to_integer(tok_ep)));

      if pid = PID_SETUP then
        next when tok_ep /= x"0";

        rx_wait(rx, rx_len, response_timeout_c);

        if rx_len /= 11 then
          log_warning(ctx_c, "SETUP data packet has " & to_string(rx_len) & " bytes");
          next;
        end if;

        if pid_get(rx(0)) /= PID_DATA0 then
          log_warning(ctx_c, "SETUP data packet is not a DATA0");
        end if;

        if not crc_is_valid(data_crc_params_c, rx(1 to 10)) then
          log_warning(ctx_c, "SETUP data packet CRC16 mismatch");
          next;
        end if;

        setup := setup_unpack(rx(1 to 8));
        ls_packet_send(device_drive, PID_ACK);

        ctrl_stall := false;
        ctrl_len := 0;
        ctrl_off := 0;
        ctrl_toggle := '1';

        if setup.rtype /= SETUP_TYPE_STANDARD
          or setup.recipient /= SETUP_RECIPIENT_DEVICE then
          ctrl_stall := true;
        elsif setup.request = REQUEST_GET_DESCRIPTOR then
          dtype := descriptor_type_from_value(setup.value);
          if dtype = DESCRIPTOR_TYPE_DEVICE then
            ctrl_len := dev_desc_c'length;
            ctrl_buf(0 to ctrl_len-1) := dev_desc_c;
          elsif dtype = DESCRIPTOR_TYPE_CONFIGURATION then
            ctrl_len := cfg_desc_c'length;
            ctrl_buf(0 to ctrl_len-1) := cfg_desc_c;
          else
            ctrl_stall := true;
          end if;

          if ctrl_len > to_integer(setup.length) then
            ctrl_len := to_integer(setup.length);
          end if;

          log_info(ctx_c, "GET_DESCRIPTOR, returning "
                   & to_string(ctrl_len) & " bytes");
        elsif setup.request = REQUEST_SET_ADDRESS then
          new_addr := device_address_t(setup.value(6 downto 0));
          addr_pending := true;
          log_info(ctx_c, "SET_ADDRESS " & to_string(to_integer(new_addr)));
        elsif setup.request = REQUEST_SET_CONFIGURATION then
          configured := to_integer(setup.value) /= 0;
          log_info(ctx_c, "SET_CONFIGURATION " & to_string(to_integer(setup.value)));
        else
          ctrl_stall := true;
        end if;

        if ctrl_stall then
          log_info(ctx_c, "Unsupported request, endpoint 0 will stall");
        end if;

      elsif pid = PID_OUT then
        rx_wait(rx, rx_len, response_timeout_c);

        if rx_len < 3 then
          log_warning(ctx_c, "OUT data packet has " & to_string(rx_len) & " bytes");
        elsif not crc_is_valid(data_crc_params_c, rx(1 to rx_len-1)) then
          log_warning(ctx_c, "OUT data packet CRC16 mismatch");
        else
          ls_packet_send(device_drive, PID_ACK);
        end if;

      elsif tok_ep = x"0" then
        if ctrl_stall then
          ls_packet_send(device_drive, PID_STALL);
        elsif setup.direction = DEVICE_TO_HOST then
          chunk := ctrl_len - ctrl_off;
          if chunk > ep0_mps_c then
            chunk := ep0_mps_c;
          end if;

          ls_packet_send(device_drive, ls_data_pid(ctrl_toggle),
                         ls_data_with_crc(ctrl_buf(ctrl_off to ctrl_off + chunk - 1)));
          rx_wait(rx, rx_len, response_timeout_c);

          if is_ack(rx, rx_len) then
            ctrl_off := ctrl_off + chunk;
            ctrl_toggle := not ctrl_toggle;
          else
            log_warning(ctx_c, "Data stage packet was not acknowledged");
          end if;
        else
          ls_packet_send(device_drive, ls_data_pid('1'),
                         ls_data_with_crc(null_byte_string));
          rx_wait(rx, rx_len, response_timeout_c);

          if is_ack(rx, rx_len) then
            if addr_pending then
              dev_addr := new_addr;
              addr_pending := false;
              log_info(ctx_c, "Now answering at address "
                       & to_string(to_integer(dev_addr)));
            end if;
          else
            log_warning(ctx_c, "Status stage packet was not acknowledged");
          end if;
        end if;

      elsif to_integer(tok_ep) = interrupt_ep_c then
        if configured and report_valid_i = '1' then
          ls_packet_send(device_drive, ls_data_pid(ep_toggle),
                         ls_data_with_crc(report_data_i(0 to report_length_i - 1),
                                          crc_corrupt_i = '1'));
          rx_wait(rx, rx_len, response_timeout_c);

          if is_ack(rx, rx_len) then
            ep_toggle := not ep_toggle;
            report_ready_o <= '1';
            wait for ls_bit_time_c;
            report_ready_o <= '0';
            log_info(ctx_c, "Report consumed");
          else
            log_info(ctx_c, "Report not acknowledged, keeping it for next poll");
          end if;
        else
          ls_packet_send(device_drive, PID_NAK);
        end if;

      else
        ls_packet_send(device_drive, PID_STALL);
      end if;
    end loop;
  end process;

end architecture;
