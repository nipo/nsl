library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_simulation;
use nsl_usb.usb.all;
use nsl_usb.io.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

-- Wire-level (D+/D-) helpers for low-speed USB simulation.
--
-- Low speed signalling is inverted with respect to full speed: the
-- device pulls D- up, so the idle/J state has D+ low and D- high.  All
-- the symbol handling below abides by that convention.
package ls_bfm is

  -- 1.5 Mb/s
  constant ls_bit_time_c: time := 666667 ps;

  -- Silence a transmitter leaves on the bus before driving its first
  -- symbol.  Covers both the host-to-device and device-to-host
  -- turnaround.
  constant ls_turnaround_c: time := 2 * ls_bit_time_c;

  -- Longest payload the helpers below hand back to their caller.
  constant ls_payload_max_c: natural := 64;

  function ls_symbol_dp(sym: usb_symbol_t) return std_ulogic;
  function ls_symbol_dm(sym: usb_symbol_t) return std_ulogic;
  function ls_symbol_get(dp, dm: std_ulogic) return usb_symbol_t;
  function ls_symbol_toggle(sym: usb_symbol_t) return usb_symbol_t;

  -- DATA0 for '0', DATA1 for '1'.
  function ls_data_pid(toggle: std_ulogic) return pid_t;

  -- Appends the packet CRC16 to a payload.  When corrupt is set, the
  -- appended value is mangled, which lets a testbench exercise the
  -- receiver error path.
  function ls_data_with_crc(data: byte_string;
                            corrupt: boolean := false) return byte_string;

  -- Serializes a packet (PID byte and everything that follows) as the
  -- symbol sequence to put on the wire: SYNC, NRZI-encoded and
  -- bit-stuffed payload, then EOP.
  function ls_packet_symbols(packet: byte_string) return usb_symbol_vector;

  -- Outcome of an IN transaction.
  type ls_in_result_t is
  record
    -- Device transmitted nothing before the timeout elapsed.
    timeout: boolean;
    pid: pid_t;
    -- Only meaningful for data packets.
    crc_ok: boolean;
    length: natural;
    data: byte_string(0 to ls_payload_max_c-1);
  end record;

  -- Stops driving the bus.
  procedure ls_bus_release(signal c: out usb_io_c);

  -- Drives SE0 long enough for the device to see a bus reset.
  procedure ls_reset(signal c: out usb_io_c;
                     duration: time := 10 ms);

  -- Bare EOP, which a low-speed device must ignore.
  procedure ls_keepalive(signal c: out usb_io_c);

  procedure ls_symbols_send(signal c: out usb_io_c;
                            syms: usb_symbol_vector);

  procedure ls_packet_send(signal c: out usb_io_c;
                           packet: byte_string);

  procedure ls_packet_send(signal c: out usb_io_c;
                           pid: pid_t;
                           data: byte_string := null_byte_string);

  procedure ls_token_send(signal c: out usb_io_c;
                          pid: pid_t;
                          addr: device_address_t;
                          ep: endpoint_no_t);

  -- Decodes one packet, assuming the caller is positioned on the
  -- leading edge of the first K of the SYNC field.  Returns once the
  -- EOP is over.  Handed-back bytes are the packet as it came, PID
  -- byte and CRC included.
  procedure ls_packet_decode(signal s: in usb_io_s;
                             variable data: out byte_string;
                             variable length: out natural);

  -- Releases the bus and decodes the next packet a device transmits.
  -- A null length means nothing came before the timeout.
  procedure ls_packet_receive(signal c: out usb_io_c;
                              signal s: in usb_io_s;
                              variable data: out byte_string;
                              variable length: out natural;
                              timeout: time := 20 * ls_bit_time_c);

  -- Token, then data packet, then handshake.
  procedure ls_transfer_setup(signal c: out usb_io_c;
                              signal s: in usb_io_s;
                              addr: device_address_t;
                              ep: endpoint_no_t;
                              data: byte_string;
                              variable acked: out boolean);

  procedure ls_transfer_out(signal c: out usb_io_c;
                            signal s: in usb_io_s;
                            addr: device_address_t;
                            ep: endpoint_no_t;
                            toggle: std_ulogic;
                            data: byte_string;
                            variable acked: out boolean);

  -- Token, then whatever the device answers.  No handshake is sent
  -- back, the caller decides.
  procedure ls_transfer_in(signal c: out usb_io_c;
                           signal s: in usb_io_s;
                           addr: device_address_t;
                           ep: endpoint_no_t;
                           variable rsp: out ls_in_result_t);

  -- IN transaction that acknowledges a data packet whose CRC16 checks
  -- out, and stays silent otherwise.
  procedure ls_interrupt_poll(signal c: out usb_io_c;
                              signal s: in usb_io_s;
                              addr: device_address_t;
                              ep: endpoint_no_t;
                              variable rsp: out ls_in_result_t);

  -- Full device-to-host control transfer, status stage included.
  procedure ls_control_read(signal c: out usb_io_c;
                            signal s: in usb_io_s;
                            addr: device_address_t;
                            setup: setup_t;
                            variable data: out byte_string;
                            variable length: out natural;
                            variable ok: out boolean;
                            mps: natural := 8);

  -- Host-to-device control transfer with no data stage.
  procedure ls_control_write(signal c: out usb_io_c;
                             signal s: in usb_io_s;
                             addr: device_address_t;
                             setup: setup_t;
                             variable ok: out boolean);

  component ls_device_bfm is
    generic(
      device_descriptor_c: byte_string;
      config_descriptor_c: byte_string;
      interrupt_ep_c: natural := 1
      );
    port(
      host_i: in usb_io_c;
      host_o: out usb_io_s;

      present_i: in std_ulogic := '1';

      report_data_i: in byte_string(0 to 7) := (others => x"00");
      report_length_i: in natural range 0 to 8 := 0;
      report_valid_i: in std_ulogic := '0';
      report_ready_o: out std_ulogic;

      crc_corrupt_i: in std_ulogic := '0'
      );
  end component;

end package;

package body ls_bfm is

  -- Wire-level events are logged by both ends of the link, transaction
  -- level ones only by the host-side helpers.
  constant wire_ctx_c: log_context := "ls-wire";
  constant ctx_c: log_context := "ls-host";

  constant sync_byte_c: byte := x"80";

  function ls_symbol_dp(sym: usb_symbol_t) return std_ulogic
  is
  begin
    case sym is
      when USB_SYMBOL_K => return '1';
      when USB_SYMBOL_SE1 => return '1';
      when others => return '0';
    end case;
  end function;

  function ls_symbol_dm(sym: usb_symbol_t) return std_ulogic
  is
  begin
    case sym is
      when USB_SYMBOL_J => return '1';
      when USB_SYMBOL_SE1 => return '1';
      when others => return '0';
    end case;
  end function;

  function ls_symbol_get(dp, dm: std_ulogic) return usb_symbol_t
  is
  begin
    if dp = '1' and dm = '1' then
      return USB_SYMBOL_SE1;
    elsif dp = '1' then
      return USB_SYMBOL_K;
    elsif dm = '1' then
      return USB_SYMBOL_J;
    else
      return USB_SYMBOL_SE0;
    end if;
  end function;

  function ls_symbol_toggle(sym: usb_symbol_t) return usb_symbol_t
  is
  begin
    if sym = USB_SYMBOL_J then
      return USB_SYMBOL_K;
    else
      return USB_SYMBOL_J;
    end if;
  end function;

  function ls_data_pid(toggle: std_ulogic) return pid_t
  is
  begin
    if toggle = '0' then
      return PID_DATA0;
    else
      return PID_DATA1;
    end if;
  end function;

  function ls_data_with_crc(data: byte_string;
                            corrupt: boolean := false) return byte_string
  is
    constant check_c: byte_string(0 to 1)
      := crc_spill(data_crc_params_c,
                   crc_update(data_crc_params_c,
                              crc_init(data_crc_params_c),
                              data));
    variable ret: byte_string(0 to data'length+1);
  begin
    ret(0 to data'length-1) := data;
    ret(data'length to data'length+1) := check_c;
    if corrupt then
      ret(data'length) := ret(data'length) xor x"ff";
    end if;
    return ret;
  end function;

  function ls_packet_symbols(packet: byte_string) return usb_symbol_vector
  is
    constant stream_c: byte_string(0 to packet'length) := sync_byte_c & packet;
    variable ret: usb_symbol_vector(0 to stream_c'length * 8 * 7 / 6 + 8);
    variable sym: usb_symbol_t := USB_SYMBOL_J;
    variable ones: natural := 0;
    variable idx: natural := 0;
  begin
    for i in stream_c'range
    loop
      for j in 0 to 7
      loop
        if stream_c(i)(j) = '0' then
          sym := ls_symbol_toggle(sym);
          ones := 0;
        else
          ones := ones + 1;
        end if;
        ret(idx) := sym;
        idx := idx + 1;

        if ones = 6 then
          sym := ls_symbol_toggle(sym);
          ret(idx) := sym;
          idx := idx + 1;
          ones := 0;
        end if;
      end loop;
    end loop;

    ret(idx) := USB_SYMBOL_SE0;
    ret(idx+1) := USB_SYMBOL_SE0;
    ret(idx+2) := USB_SYMBOL_J;

    return ret(0 to idx+2);
  end function;

  procedure ls_bus_release(signal c: out usb_io_c)
  is
  begin
    c.oe <= '0';
    c.dp <= '0';
    c.dm <= '0';
    c.dp_pullup_en <= '0';
  end procedure;

  procedure ls_reset(signal c: out usb_io_c;
                     duration: time := 10 ms)
  is
  begin
    log_info(ctx_c, "Bus reset, SE0 for " & to_string(duration));
    c.oe <= '1';
    c.dp <= '0';
    c.dm <= '0';
    c.dp_pullup_en <= '0';
    wait for duration;
    ls_bus_release(c);
    wait for 10 * ls_bit_time_c;
  end procedure;

  procedure ls_keepalive(signal c: out usb_io_c)
  is
    constant eop_c: usb_symbol_vector(0 to 2)
      := (USB_SYMBOL_SE0, USB_SYMBOL_SE0, USB_SYMBOL_J);
  begin
    ls_symbols_send(c, eop_c);
  end procedure;

  procedure ls_symbols_send(signal c: out usb_io_c;
                            syms: usb_symbol_vector)
  is
  begin
    wait for ls_turnaround_c;

    c.oe <= '1';
    c.dp_pullup_en <= '0';
    for i in syms'range
    loop
      c.dp <= ls_symbol_dp(syms(i));
      c.dm <= ls_symbol_dm(syms(i));
      wait for ls_bit_time_c;
    end loop;
    ls_bus_release(c);
  end procedure;

  procedure ls_packet_send(signal c: out usb_io_c;
                           packet: byte_string)
  is
  begin
    log_debug(wire_ctx_c, "> " & to_hex_string(packet));
    ls_symbols_send(c, ls_packet_symbols(packet));
  end procedure;

  procedure ls_packet_send(signal c: out usb_io_c;
                           pid: pid_t;
                           data: byte_string := null_byte_string)
  is
    constant packet_c: byte_string(0 to data'length) := pid_byte(pid) & data;
  begin
    ls_packet_send(c, packet_c);
  end procedure;

  procedure ls_token_send(signal c: out usb_io_c;
                          pid: pid_t;
                          addr: device_address_t;
                          ep: endpoint_no_t)
  is
  begin
    ls_packet_send(c, pid, token_data(addr, ep));
  end procedure;

  procedure ls_packet_decode(signal s: in usb_io_s;
                             variable data: out byte_string;
                             variable length: out natural)
  is
    variable sym, prev: usb_symbol_t := USB_SYMBOL_J;
    variable ones: natural := 0;
    variable bit_index: natural := 0;
    variable count: natural := 0;
    variable acc: byte := (others => '0');
    variable in_sync: boolean := true;
    variable first: boolean := true;
    variable b: std_ulogic;
  begin
    length := 0;

    loop
      if first then
        wait for ls_bit_time_c / 2;
        first := false;
      else
        wait for ls_bit_time_c;
      end if;

      sym := ls_symbol_get(s.dp, s.dm);
      exit when sym = USB_SYMBOL_SE0;

      if sym = USB_SYMBOL_SE1 then
        log_error(wire_ctx_c, "SE1 seen in a packet");
        exit;
      end if;

      if sym = prev then
        b := '1';
      else
        b := '0';
      end if;
      prev := sym;

      if ones = 6 then
        if b /= '0' then
          log_error(wire_ctx_c, "Missing stuffed bit after six ones");
        end if;
        ones := 0;
      else
        if b = '1' then
          ones := ones + 1;
        else
          ones := 0;
        end if;

        acc := b & acc(7 downto 1);
        bit_index := bit_index + 1;

        if bit_index = 8 then
          bit_index := 0;
          if in_sync then
            if acc /= sync_byte_c then
              log_error(wire_ctx_c, "Bad SYNC field: " & to_hex_string(acc));
            end if;
            in_sync := false;
          else
            if count < data'length then
              data(data'low + count) := acc;
            end if;
            count := count + 1;
          end if;
        end if;
      end if;
    end loop;

    if bit_index /= 0 then
      log_error(wire_ctx_c, "Packet ended on a partial byte");
    end if;

    if count > data'length then
      log_error(wire_ctx_c, "Packet longer than receive buffer, truncated");
      count := data'length;
    end if;

    length := count;

    -- Sampling happened in the middle of the first SE0 bit, let the
    -- rest of the EOP go by.
    wait for ls_bit_time_c * 9 / 4;
  end procedure;

  procedure ls_packet_receive(signal c: out usb_io_c;
                              signal s: in usb_io_s;
                              variable data: out byte_string;
                              variable length: out natural;
                              timeout: time := 20 * ls_bit_time_c)
  is
  begin
    ls_bus_release(c);
    length := 0;

    wait until s.dp = '1' for timeout;
    if s.dp /= '1' then
      return;
    end if;

    ls_packet_decode(s, data, length);
  end procedure;

  procedure ls_handshake_receive(signal c: out usb_io_c;
                                 signal s: in usb_io_s;
                                 variable acked: out boolean)
  is
    variable rx: byte_string(0 to 3);
    variable rx_len: natural;
  begin
    acked := false;
    ls_packet_receive(c, s, rx, rx_len);

    if rx_len = 0 then
      log_error(ctx_c, "No handshake from device");
      return;
    end if;

    if not pid_byte_is_correct(rx(0)) then
      log_error(ctx_c, "Malformed handshake PID " & to_hex_string(rx(0)));
      return;
    end if;

    if pid_get(rx(0)) /= PID_ACK then
      log_info(ctx_c, "Handshake is not an ACK: " & to_hex_string(rx(0)));
      return;
    end if;

    acked := true;
  end procedure;

  procedure ls_transfer_setup(signal c: out usb_io_c;
                              signal s: in usb_io_s;
                              addr: device_address_t;
                              ep: endpoint_no_t;
                              data: byte_string;
                              variable acked: out boolean)
  is
  begin
    ls_token_send(c, PID_SETUP, addr, ep);
    ls_packet_send(c, PID_DATA0, ls_data_with_crc(data));
    ls_handshake_receive(c, s, acked);
  end procedure;

  procedure ls_transfer_out(signal c: out usb_io_c;
                            signal s: in usb_io_s;
                            addr: device_address_t;
                            ep: endpoint_no_t;
                            toggle: std_ulogic;
                            data: byte_string;
                            variable acked: out boolean)
  is
  begin
    ls_token_send(c, PID_OUT, addr, ep);
    ls_packet_send(c, ls_data_pid(toggle), ls_data_with_crc(data));
    ls_handshake_receive(c, s, acked);
  end procedure;

  procedure ls_transfer_in(signal c: out usb_io_c;
                           signal s: in usb_io_s;
                           addr: device_address_t;
                           ep: endpoint_no_t;
                           variable rsp: out ls_in_result_t)
  is
    variable rx: byte_string(0 to ls_payload_max_c + 2);
    variable rx_len: natural;
    variable ret: ls_in_result_t;
  begin
    ret.timeout := true;
    ret.pid := PID_RESERVED;
    ret.crc_ok := false;
    ret.length := 0;
    ret.data := (others => x"00");

    ls_token_send(c, PID_IN, addr, ep);
    ls_packet_receive(c, s, rx, rx_len);

    if rx_len = 0 then
      rsp := ret;
      return;
    end if;

    ret.timeout := false;

    if not pid_byte_is_correct(rx(0)) then
      log_error(ctx_c, "Malformed PID " & to_hex_string(rx(0)));
      rsp := ret;
      return;
    end if;

    ret.pid := pid_get(rx(0));

    if ret.pid = PID_DATA0 or ret.pid = PID_DATA1 then
      if rx_len < 3 then
        log_error(ctx_c, "Data packet shorter than its CRC");
      else
        ret.crc_ok := crc_is_valid(data_crc_params_c, rx(1 to rx_len-1));
        ret.length := rx_len - 3;
        ret.data(0 to ret.length-1) := rx(1 to rx_len-3);
      end if;
    else
      ret.crc_ok := true;
    end if;

    rsp := ret;
  end procedure;

  procedure ls_interrupt_poll(signal c: out usb_io_c;
                              signal s: in usb_io_s;
                              addr: device_address_t;
                              ep: endpoint_no_t;
                              variable rsp: out ls_in_result_t)
  is
    variable ret: ls_in_result_t;
  begin
    ls_transfer_in(c, s, addr, ep, ret);

    if not ret.timeout
      and (ret.pid = PID_DATA0 or ret.pid = PID_DATA1)
      and ret.crc_ok then
      ls_packet_send(c, PID_ACK);
    end if;

    rsp := ret;
  end procedure;

  procedure ls_control_read(signal c: out usb_io_c;
                            signal s: in usb_io_s;
                            addr: device_address_t;
                            setup: setup_t;
                            variable data: out byte_string;
                            variable length: out natural;
                            variable ok: out boolean;
                            mps: natural := 8)
  is
    variable rsp: ls_in_result_t;
    variable acked: boolean;
    variable off, want: natural := 0;
    variable toggle: std_ulogic := '1';
  begin
    length := 0;
    ok := false;

    log_info(ctx_c, "Control read @" & to_string(to_integer(addr))
             & " request " & to_hex_string(byte(setup.request))
             & " value " & to_hex_string(std_ulogic_vector(setup.value)));

    ls_transfer_setup(c, s, addr, x"0", setup_pack(setup), acked);
    if not acked then
      log_error(ctx_c, "SETUP stage was not acknowledged");
      return;
    end if;

    want := to_integer(setup.length);

    while off < want
    loop
      ls_transfer_in(c, s, addr, x"0", rsp);

      if rsp.timeout then
        log_error(ctx_c, "No answer to IN token");
        return;
      end if;

      if rsp.pid /= PID_DATA0 and rsp.pid /= PID_DATA1 then
        log_error(ctx_c, "Data stage answered with " & to_hex_string(std_ulogic_vector(rsp.pid)));
        return;
      end if;

      if not rsp.crc_ok then
        log_error(ctx_c, "Data stage CRC16 mismatch");
        return;
      end if;

      if rsp.pid /= ls_data_pid(toggle) then
        log_warning(ctx_c, "Unexpected data toggle in data stage");
      end if;

      ls_packet_send(c, PID_ACK);

      for i in 0 to rsp.length-1
      loop
        if off + i < data'length then
          data(data'low + off + i) := rsp.data(i);
        end if;
      end loop;

      off := off + rsp.length;
      toggle := not toggle;

      exit when rsp.length < mps;
    end loop;

    if off > data'length then
      log_error(ctx_c, "Device returned more than the caller buffer holds");
      off := data'length;
    end if;

    length := off;

    ls_transfer_out(c, s, addr, x"0", '1', null_byte_string, acked);
    if not acked then
      log_error(ctx_c, "Status stage was not acknowledged");
      return;
    end if;

    ok := true;
  end procedure;

  procedure ls_control_write(signal c: out usb_io_c;
                             signal s: in usb_io_s;
                             addr: device_address_t;
                             setup: setup_t;
                             variable ok: out boolean)
  is
    variable rsp: ls_in_result_t;
    variable acked: boolean;
  begin
    ok := false;

    log_info(ctx_c, "Control write @" & to_string(to_integer(addr))
             & " request " & to_hex_string(byte(setup.request))
             & " value " & to_hex_string(std_ulogic_vector(setup.value)));

    ls_transfer_setup(c, s, addr, x"0", setup_pack(setup), acked);
    if not acked then
      log_error(ctx_c, "SETUP stage was not acknowledged");
      return;
    end if;

    ls_transfer_in(c, s, addr, x"0", rsp);

    if rsp.timeout then
      log_error(ctx_c, "No answer to status stage IN token");
      return;
    end if;

    if rsp.pid /= PID_DATA0 and rsp.pid /= PID_DATA1 then
      log_error(ctx_c, "Status stage answered with " & to_hex_string(std_ulogic_vector(rsp.pid)));
      return;
    end if;

    if rsp.length /= 0 then
      log_error(ctx_c, "Status stage carried data");
      return;
    end if;

    ls_packet_send(c, PID_ACK);

    ok := true;
  end procedure;

end package body;
