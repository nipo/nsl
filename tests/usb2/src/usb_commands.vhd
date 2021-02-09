library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_usb, nsl_data, nsl_simulation, nsl_math;
use nsl_usb.usb.all;
use nsl_usb.utmi.all;
use nsl_usb.debug.all;
use nsl_simulation.logging.all;
use nsl_simulation.text.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;

package usb_commands is
  
  type utmi8_s2p is
  record
    data : utmi_data8_sie2phy;
    system : utmi_system_sie2phy;
  end record;

  type utmi8_p2s is
  record
    data : utmi_data8_phy2sie;
    system : utmi_system_phy2sie;
  end record;

  procedure utmi_init(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s);
  procedure utmi_reset(signal s2p: in utmi8_s2p;
                       signal p2s: out utmi8_p2s);
  procedure utmi_wait(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s;
                      duration: time);
  procedure utmi_wait(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s;
                      cycles : integer);
  procedure utmi_hs_handshake(signal s2p: in utmi8_s2p;
                              signal p2s: out utmi8_p2s);
  procedure utmi_cycle(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s);

  procedure utmi_sof(signal s2p: in utmi8_s2p;
                     signal p2s: out utmi8_p2s;
                     frame : unsigned);

  procedure utmi_packet_send(signal s2p: in utmi8_s2p;
                          signal p2s: out utmi8_p2s;
                          pid : pid_t;
                          data : byte_string := null_byte_string);

  procedure utmi_packet_receive(signal s2p: in utmi8_s2p;
                                signal p2s: out utmi8_p2s;
                                pid : pid_t;
                                data : byte_string := null_byte_string);
  
  procedure utmi_transfer_out(signal s2p: in utmi8_s2p;
                              signal p2s: out utmi8_p2s;
                              dev_addr : unsigned;
                              ep_no : endpoint_no_t;
                              toggle : std_ulogic;
                              hex_data : string := "";
                              handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_out(signal s2p: in utmi8_s2p;
                              signal p2s: out utmi8_p2s;
                              dev_addr : unsigned;
                              ep_no : endpoint_no_t;
                              toggle : std_ulogic;
                              data : byte_string := null_byte_string;
                              handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_setup(signal s2p: in utmi8_s2p;
                                signal p2s: out utmi8_p2s;
                                dev_addr : unsigned;
                                ep_no : endpoint_no_t;
                                hex_data : string := "";
                                handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_setup(signal s2p: in utmi8_s2p;
                                signal p2s: out utmi8_p2s;
                                dev_addr : unsigned;
                                ep_no : endpoint_no_t;
                                data : byte_string := null_byte_string;
                                handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_in(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             dev_addr : unsigned;
                             ep_no : endpoint_no_t;
                             toggle : std_ulogic;
                             hex_data : string := "";
                             handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_in(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             dev_addr : unsigned;
                             ep_no : endpoint_no_t;
                             toggle : std_ulogic;
                             data : byte_string := null_byte_string;
                             handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_in(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             dev_addr : unsigned;
                             ep_no : endpoint_no_t;
                             error_pid : pid_t := PID_RESERVED);

  procedure utmi_transfer_ping(signal s2p: in utmi8_s2p;
                               signal p2s: out utmi8_p2s;
                               dev_addr : unsigned;
                               ep_no : endpoint_no_t;
                               handshake_pid : pid_t := PID_RESERVED);

  procedure utmi_control_write(
    signal s2p: in utmi8_s2p;
    signal p2s: out utmi8_p2s;
    dev_addr : unsigned;
    ep_no : endpoint_no_t := x"0";
    rtype : setup_type_t := SETUP_TYPE_STANDARD;
    recipient : setup_recipient_t := SETUP_RECIPIENT_DEVICE;
    request : setup_request_t;
    value, index : unsigned := "0";
    data : string := "");

  procedure utmi_control_read(
    signal s2p: in utmi8_s2p;
    signal p2s: out utmi8_p2s;
    dev_addr : unsigned;
    ep_no : endpoint_no_t := x"0";
    rtype : setup_type_t := SETUP_TYPE_STANDARD;
    recipient : setup_recipient_t := SETUP_RECIPIENT_DEVICE;
    request : setup_request_t;
    value, index, length : unsigned := "0";
    blob : byte_string := null_byte_string;
    mps : integer := 64);

  procedure utmi_control_read(
    signal s2p: in utmi8_s2p;
    signal p2s: out utmi8_p2s;
    dev_addr : unsigned;
    ep_no : endpoint_no_t := x"0";
    rtype : setup_type_t := SETUP_TYPE_STANDARD;
    recipient : setup_recipient_t := SETUP_RECIPIENT_DEVICE;
    request : setup_request_t;
    value, index, length : unsigned := "0";
    data : string := "";
    mps : integer := 64);

  constant cycle_time : time := 16666 ps;

end usb_commands;

package body usb_commands is
  
  procedure utmi_init(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s)
  is
  begin
    log_debug("* Init");
    p2s.system.line_state <= USB_SYMBOL_SE0;
    p2s.system.clock <= '0';
    p2s.data.tx_ready <= '0';
    p2s.data.rx_active <= '0';
    p2s.data.rx_error <= '0';
    p2s.data.rx_valid <= '0';
    p2s.data.data <= (others => '-');
  end procedure;

  procedure utmi_wait(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s;
                      duration: time)
  is
    variable elapsed : time := 0 ps;
  begin
    log_debug("* Waiting " & to_string(duration));
    while elapsed < duration
    loop
      utmi_cycle(s2p, p2s);
      elapsed := elapsed + cycle_time;
    end loop;
  end procedure;

  procedure utmi_wait(signal s2p: in utmi8_s2p;
                      signal p2s: out utmi8_p2s;
                      cycles : integer)
  is
    variable elapsed : time := 0 ps;
  begin
--    log_debug("* Waiting " & to_string(cycles) & " cycles");
    for i in 0 to cycles - 1
    loop
      utmi_cycle(s2p, p2s);
    end loop;
  end procedure;

  procedure utmi_wait_tx_to_tx(signal s2p: in utmi8_s2p;
                               signal p2s: out utmi8_p2s)
  is
  begin
    utmi_wait(s2p, p2s, 16);
  end procedure;

  procedure utmi_wait_rx_to_tx(signal s2p: in utmi8_s2p;
                               signal p2s: out utmi8_p2s)
  is
  begin
    utmi_wait(s2p, p2s, 32);
  end procedure;

  procedure utmi_reset(signal s2p: in utmi8_s2p;
                       signal p2s: out utmi8_p2s)
  is
  begin
    p2s.system.line_state <= USB_SYMBOL_SE0;
    utmi_wait(s2p, p2s, 300 us);
  end procedure;

  procedure utmi_cycle(signal s2p: in utmi8_s2p;
                       signal p2s: out utmi8_p2s)
  is
  begin
    wait for cycle_time / 4;
    p2s.system.clock <= '1';
    wait for cycle_time / 2;
    p2s.system.clock <= '0';
    wait for cycle_time / 4;
  end procedure;

  procedure utmi_hs_handshake(signal s2p: in utmi8_s2p;
                              signal p2s: out utmi8_p2s)
  is
  begin
    wait_chirp_end: while true
    loop
      utmi_cycle(s2p, p2s);
      exit when s2p.data.tx_valid = '0';
    end loop;

    for i in 0 to 5
    loop
      p2s.system.line_state <= USB_SYMBOL_K;
      utmi_wait(s2p, p2s, 3 us);
      p2s.system.line_state <= USB_SYMBOL_J;
      utmi_wait(s2p, p2s, 3 us);
    end loop;

    utmi_wait(s2p, p2s, 3 us);
    
  end procedure;

  procedure utmi_packet_send(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             pid : pid_t;
                             data : byte_string := null_byte_string)
  is
    constant packet : byte_string := pid_byte(pid) & data;
  begin
    log_debug("   > " & packet_to_string(packet));

    p2s.data.rx_active <= '1';
    p2s.data.rx_valid <= '0';
    utmi_cycle(s2p, p2s);
    for i in packet'range
    loop
      p2s.data.rx_valid <= '1';
      p2s.data.data <= packet(i);
      utmi_cycle(s2p, p2s);
    end loop;
    p2s.data.data <= (others => '-');
    p2s.data.rx_valid <= '0';
    utmi_cycle(s2p, p2s);
    p2s.data.rx_active <= '0';
    utmi_cycle(s2p, p2s);

    utmi_wait_tx_to_tx(s2p, p2s);
  end procedure;

  procedure utmi_packet_receive(signal s2p: in utmi8_s2p;
                                signal p2s: out utmi8_p2s;
                                pid : pid_t;
                                data : byte_string := null_byte_string)
  is
    constant packet : byte_string := pid_byte(pid) & data;
    variable rxdata : byte_string(0 to 8191 + 3);
    variable rx_ptr : integer range rxdata'left to rxdata'right;
  begin
    log_debug("   < " & packet_to_string(packet));

    rx_ptr := 0;
    p2s.data.rx_active <= '0';
    p2s.data.rx_valid <= '0';
    utmi_cycle(s2p, p2s);

    wait_transmit: while true
    loop
      utmi_cycle(s2p, p2s);
      exit when s2p.data.tx_valid = '1';
    end loop;

    p2s.data.tx_ready <= '1';

    wait_end: while true
    loop
      rxdata(rx_ptr) := s2p.data.data;
      rx_ptr := rx_ptr + 1;
      utmi_cycle(s2p, p2s);
      exit when s2p.data.tx_valid = '0';
    end loop;

    p2s.data.tx_ready <= '0';

    utmi_cycle(s2p, p2s);

    if rx_ptr /= packet'length or rxdata(0 to rx_ptr-1) /= packet then
      log_debug("   ! " & packet_to_string(rxdata(0 to rx_ptr-1)) & " (Received)");
      log_error("   ! " & to_hex_string(rxdata(0 to rx_ptr-1)));
      log_error("   Received packet does not match");
    end if;

    utmi_wait_rx_to_tx(s2p, p2s);
  end procedure;

  function packet_data_with_crc(data : byte_string) return byte_string
  is
  begin
    return data & to_le(unsigned(data_crc_update(data_crc_init, data)));
  end function;

  function packet_data_with_crc(hex_data : string) return byte_string
  is
  begin
    return packet_data_with_crc(from_hex(hex_data));
  end function;

  procedure utmi_sof(signal s2p: in utmi8_s2p;
                     signal p2s: out utmi8_p2s;
                     frame : unsigned)
  is
  begin
    log_debug("  Sof transfer " & to_string(frame));
    utmi_packet_send(s2p, p2s, PID_SOF,
                     sof_data(frame_no_t(resize(frame, frame_no_t'length))));
  end procedure;
  
  procedure utmi_transfer_out(signal s2p: in utmi8_s2p;
                              signal p2s: out utmi8_p2s;
                              dev_addr : unsigned;
                              ep_no : endpoint_no_t;
                              toggle : std_ulogic;
                              data : byte_string := null_byte_string;
                              handshake_pid : pid_t := PID_RESERVED)
  is
    variable data_pid : pid_t;
  begin
    log_debug("  Out transfer @ " & to_string(dev_addr) & " ep " & to_string(ep_no));
    if toggle = '0' then
      data_pid := PID_DATA0;
    else
      data_pid := PID_DATA1;
    end if;
    
    utmi_packet_send(s2p, p2s, PID_OUT, token_data(device_address_t(resize(dev_addr, device_address_t'length)), ep_no));
    utmi_packet_send(s2p, p2s, data_pid, packet_data_with_crc(data));
    if handshake_pid /= PID_RESERVED then
      utmi_packet_receive(s2p, p2s, handshake_pid);
    end if;
  end procedure;

  procedure utmi_transfer_setup(signal s2p: in utmi8_s2p;
                                signal p2s: out utmi8_p2s;
                                dev_addr : unsigned;
                                ep_no : endpoint_no_t;
                                data : byte_string := null_byte_string;
                                handshake_pid : pid_t := PID_RESERVED)
  is
  begin
    log_debug("  Setup transfer @ " & to_string(dev_addr) & " ep " & to_string(ep_no));
    utmi_packet_send(s2p, p2s, PID_SETUP, token_data(device_address_t(resize(dev_addr, device_address_t'length)), ep_no));
    utmi_packet_send(s2p, p2s, PID_DATA0, packet_data_with_crc(data));
    if handshake_pid /= PID_RESERVED then
      utmi_packet_receive(s2p, p2s, handshake_pid);
    end if;
  end procedure;

  procedure utmi_transfer_in(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             dev_addr : unsigned;
                             ep_no : endpoint_no_t;
                             toggle : std_ulogic;
                             data : byte_string := null_byte_string;
                             handshake_pid : pid_t := PID_RESERVED)
  is
    variable data_pid : pid_t;
  begin
    log_debug("  In transfer @ " & to_string(dev_addr)
              & " ep " & to_string(ep_no)
              & ", " & to_string(data'length) & " bytes expected");
    if toggle = '0' then
      data_pid := PID_DATA0;
    else
      data_pid := PID_DATA1;
    end if;
    
    utmi_packet_send(s2p, p2s, PID_IN, token_data(device_address_t(resize(dev_addr, device_address_t'length)), ep_no));
    utmi_packet_receive(s2p, p2s, data_pid, packet_data_with_crc(data));
    if handshake_pid /= PID_RESERVED then
      utmi_packet_send(s2p, p2s, handshake_pid);
    end if;
  end procedure;

  procedure utmi_transfer_out(signal s2p: in utmi8_s2p;
                              signal p2s: out utmi8_p2s;
                              dev_addr : unsigned;
                              ep_no : endpoint_no_t;
                              toggle : std_ulogic;
                              hex_data : string := "";
                              handshake_pid : pid_t := PID_RESERVED)
  is
  begin
    utmi_transfer_out(s2p, p2s, dev_addr, ep_no, toggle, from_hex(hex_data), handshake_pid);
  end procedure;

  procedure utmi_transfer_setup(signal s2p: in utmi8_s2p;
                                signal p2s: out utmi8_p2s;
                                dev_addr : unsigned;
                                ep_no : endpoint_no_t;
                                hex_data : string := "";
                                handshake_pid : pid_t := PID_RESERVED)
  is
  begin
    utmi_transfer_setup(s2p, p2s, dev_addr, ep_no, from_hex(hex_data), handshake_pid);
  end procedure;

  procedure utmi_transfer_in(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             dev_addr : unsigned;
                             ep_no : endpoint_no_t;
                             toggle : std_ulogic;
                             hex_data : string := "";
                             handshake_pid : pid_t := PID_RESERVED)
  is
  begin
    utmi_transfer_in(s2p, p2s, dev_addr, ep_no, toggle, from_hex(hex_data), handshake_pid);
  end procedure;

  procedure utmi_transfer_in(signal s2p: in utmi8_s2p;
                             signal p2s: out utmi8_p2s;
                             dev_addr : unsigned;
                             ep_no : endpoint_no_t;
                             error_pid : pid_t := PID_RESERVED)
  is
  begin
    log_debug("  In transfer @ " & to_string(dev_addr) & " ep " & to_string(ep_no));
    utmi_packet_send(s2p, p2s, PID_IN, token_data(device_address_t(resize(dev_addr, device_address_t'length)), ep_no));
    if error_pid /= PID_RESERVED then
      utmi_packet_receive(s2p, p2s, error_pid);
    end if;
  end procedure;

  procedure utmi_transfer_ping(signal s2p: in utmi8_s2p;
                               signal p2s: out utmi8_p2s;
                               dev_addr : unsigned;
                               ep_no : endpoint_no_t;
                               handshake_pid : pid_t := PID_RESERVED)
  is
  begin
    utmi_packet_send(s2p, p2s, PID_PING, token_data(device_address_t(resize(dev_addr, device_address_t'length)), ep_no));
    if handshake_pid /= PID_RESERVED then
      utmi_packet_receive(s2p, p2s, handshake_pid);
    end if;
  end procedure;

  procedure utmi_control_write(
    signal s2p: in utmi8_s2p;
    signal p2s: out utmi8_p2s;
    dev_addr : unsigned;
    ep_no : endpoint_no_t := x"0";
    rtype : setup_type_t := SETUP_TYPE_STANDARD;
    recipient : setup_recipient_t := SETUP_RECIPIENT_DEVICE;
    request : setup_request_t;
    value, index : unsigned := "0";
    data : string := "")
  is
    variable setup: setup_t;
    variable setup_data: byte_string(0 to 7);
  begin
    setup.direction := HOST_TO_DEVICE;
    setup.rtype := rtype;
    setup.recipient := recipient;
    setup.request := request;
    setup.value := resize(value, setup.value'length);
    setup.index := resize(index, setup.index'length);
    setup.length := to_unsigned(data'length/2, setup.index'length);
    
    log_debug(" " & to_string(setup));

    setup_data := setup_pack(setup);

    utmi_transfer_setup(s2p, p2s, dev_addr, ep_no, setup_data, PID_ACK);
    if data'length /= 0 then
      utmi_transfer_out(s2p, p2s, dev_addr, ep_no, '1', data, PID_ACK);
    end if;
    utmi_transfer_in(s2p, p2s, dev_addr, ep_no, '1', "", PID_ACK);
  end procedure;

  procedure utmi_control_read(
    signal s2p: in utmi8_s2p;
    signal p2s: out utmi8_p2s;
    dev_addr : unsigned;
    ep_no : endpoint_no_t := x"0";
    rtype : setup_type_t := SETUP_TYPE_STANDARD;
    recipient : setup_recipient_t := SETUP_RECIPIENT_DEVICE;
    request : setup_request_t;
    value, index, length : unsigned := "0";
    blob : byte_string := null_byte_string;
    mps : integer := 64)
  is
    variable setup: setup_t;
    variable setup_data: byte_string(0 to 7);
    alias xblob : byte_string(0 to blob'length-1) is blob;
    variable toggle : std_ulogic;
    variable off, s, total : integer;
    variable short : boolean;
  begin
    setup.direction := DEVICE_TO_HOST;
    setup.rtype := rtype;
    setup.recipient := recipient;
    setup.request := request;
    setup.value := resize(value, setup.value'length);
    setup.index := resize(index, setup.index'length);
    if length /= 0 then
      setup.length := resize(length, setup.index'length);
    else
      setup.length := to_unsigned(xblob'length, setup.index'length);
    end if;

    log_debug(" " & to_string(setup));

    setup_data := setup_pack(setup);

    utmi_transfer_setup(s2p, p2s, dev_addr, ep_no, setup_data, PID_ACK);

    total := xblob'length;
    toggle := '1';
    off := 0;
    short := false;
    while off < total
    loop
      s := nsl_math.arith.min(mps, total - off);

      utmi_transfer_in(s2p, p2s, dev_addr, ep_no, toggle, xblob(off to off + s - 1), PID_ACK);
      toggle := not toggle;
      off := off + s;
      short := s /= mps;
    end loop;

    if off = total and off /= length and not short then
      utmi_transfer_in(s2p, p2s, dev_addr, ep_no, toggle, null_byte_string, PID_ACK);
    end if;

    utmi_transfer_out(s2p, p2s, dev_addr, ep_no, '1', "", PID_ACK);
  end procedure;    

  procedure utmi_control_read(
    signal s2p: in utmi8_s2p;
    signal p2s: out utmi8_p2s;
    dev_addr : unsigned;
    ep_no : endpoint_no_t := x"0";
    rtype : setup_type_t := SETUP_TYPE_STANDARD;
    recipient : setup_recipient_t := SETUP_RECIPIENT_DEVICE;
    request : setup_request_t;
    value, index, length : unsigned := "0";
    data : string := "";
    mps : integer := 64)
  is
  begin
    utmi_control_read(s2p, p2s, dev_addr, ep_no,
                      rtype, recipient, request,
                      value, index, length,
                      from_hex(data), mps);
  end procedure;

end usb_commands;
