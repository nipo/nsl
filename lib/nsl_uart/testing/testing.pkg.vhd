library ieee;
use ieee.std_logic_1164.all;

library work, nsl_data, nsl_logic, nsl_simulation;
use work.serdes.all;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

package testing is

  procedure uart8_wait(
    signal serial: out std_ulogic;
    constant bit_count: integer;
    constant rate: integer);

  procedure uart8_transmit(
    signal serial: out std_ulogic;
    constant word: std_ulogic_vector;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1);

  procedure uart8_transmit(
    signal serial: out std_ulogic;
    constant stream: byte_string;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1);

  procedure uart8_receive(
    signal serial: in std_ulogic;
    word: out std_ulogic_vector;
    valid: out boolean;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1);

  procedure uart8_receive(
    signal serial: in std_ulogic;
    stream: out byte_stream;
    valid: out boolean;
    constant end_marker : byte;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1);

  procedure uart8_receive(
    signal serial: in std_ulogic;
    stream: out byte_stream;
    valid: out boolean;
    constant size : integer;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1);

  procedure uart8_check(
    signal serial: in std_ulogic;
    constant data: byte_string;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1);
  
end package;

package body testing is

  procedure uart8_wait(
    signal serial: out std_ulogic;
    constant bit_count: integer;
    constant rate: integer)
  is
    constant bit_time: time := 1e9 ns / rate;
  begin
    serial <= '1';
    wait for bit_time * bit_count;
  end procedure;

  procedure uart8_transmit(
    signal serial: out std_ulogic;
    constant word: std_ulogic_vector;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1)
  is
    constant bit_time: time := 1e9 ns / rate;
    variable to_shift: std_ulogic_vector(0 to 1 + word'length + if_else(parity /= PARITY_NONE, 1, 0) + stop - 1);
  begin
    to_shift(0) := '0';
    to_shift(1 to word'length) := bitswap(word);
    case parity is
      when PARITY_NONE =>
        to_shift(word'length + 1 to word'length + stop) := (others => '1');
        
      when PARITY_EVEN =>
        to_shift(word'length + 1) := not xor_reduce(word);
        to_shift(word'length + 2 to word'length + stop + 1) := (others => '1');

      when PARITY_ODD =>
        to_shift(word'length + 1) := xor_reduce(word);
        to_shift(word'length + 2 to word'length + stop + 1) := (others => '1');
    end case;

    for i in to_shift'range
    loop
      serial <= to_shift(i);
      wait for bit_time;
    end loop;
  end procedure;

  procedure uart8_transmit(
    signal serial: out std_ulogic;
    constant stream: byte_string;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1)
  is
  begin
    log_info("UART < " & to_string(stream));
    for i in stream'range
    loop
      uart8_transmit(serial, stream(i), rate, parity, stop);
    end loop;
  end procedure;

  procedure uart8_receive(
    signal serial: in std_ulogic;
    word: out std_ulogic_vector;
    valid: out boolean;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1)
  is
    constant bit_time: time := 1e9 ns / rate;
    variable to_shift: std_ulogic_vector(0 to word'length + if_else(parity /= PARITY_NONE, 1, 0) - 1);
  begin
    while true
    loop
      wait until falling_edge(serial);
      wait for bit_time / 2;
      if serial = '0' then
        exit;
      end if;
    end loop;
    wait for bit_time;

    for i in to_shift'range
    loop
      to_shift(i) := serial;
      wait for bit_time;
    end loop;

    case parity is
      when PARITY_NONE =>
        valid := true;
        
      when PARITY_EVEN =>
        valid := xor_reduce(to_shift) = '0';

      when PARITY_ODD =>
        valid := xor_reduce(to_shift) = '1';
    end case;
    word := bitswap(to_shift(0 to word'length-1));
  end procedure;

  procedure uart8_receive(
    signal serial: in std_ulogic;
    stream: out byte_stream;
    valid: out boolean;
    constant end_marker : byte;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1)
  is
    variable ret: byte_stream := new byte_string(1 to 0);
    variable tmp: byte;
    variable v, nv: boolean;
  begin
    v := true;
    while true
    loop
      uart8_receive(serial, tmp, nv, rate, parity, stop);
      v := v and nv;
      write(ret, tmp);
      if tmp = end_marker then
        stream := ret;
        valid := v;
        return;
      end if;
    end loop;
  end procedure;

  procedure uart8_receive(
    signal serial: in std_ulogic;
    stream: out byte_stream;
    valid: out boolean;
    constant size : integer;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1)
  is
    variable ret: byte_stream := new byte_string(0 to size - 1);
    variable v, nv: boolean;
  begin
    v := true;
    for i in ret'range
    loop
      uart8_receive(serial, ret(i), nv, rate, parity, stop);
      v := v and nv;
    end loop;
    log_info("UART > " & to_string(ret.all));
    stream := ret;
    valid := v;
  end procedure;

  procedure uart8_check(
    signal serial: in std_ulogic;
    constant data: byte_string;
    constant rate: integer;
    constant parity: parity_t := PARITY_NONE;
    constant stop: integer := 1)
  is
    variable rx: byte_stream;
    variable valid: boolean;
  begin
    uart8_receive(serial, rx, valid, data'length, rate, parity, stop);
    log_info("UART > " & to_string(rx.all) & ", " & if_else(rx.all = data, "OK", "FAIL"));
    if rx.all /= data then
      log_info("UART * " & to_string(data) & ", expected");
    end if;
    deallocate(rx);
  end procedure;

end package body;
