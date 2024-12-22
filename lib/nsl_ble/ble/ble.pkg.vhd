library ieee;
use ieee.std_logic_1164.all;

library nsl_data;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;

package ble is

  -- CRC parameters
  constant crc_params_c : crc_params_t := crc_params(
    init             => x"555555",
    poly             => x"100065b",
    complement_input => false,
    complement_state => false,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );

  constant preamble_c : byte_string := from_hex("aa");
  constant advertising_access_address_c : byte_string := from_hex("d6be898e");
  subtype whitening_state_t is std_ulogic_vector(0 to 6);
  constant whitening_poly_c: whitening_state_t := "1000100";

  procedure whitening_next(state: inout whitening_state_t;
                           w: out byte);

  function whitened(data: byte_string;
                    init: whitening_state_t) return byte_string;
  
end package ble;

package body ble is

  procedure whitening_next(state: inout whitening_state_t;
                           b: out std_ulogic)
  is
    variable next_state : whitening_state_t;
  begin
    b := state(6);
    next_state := '0' & state(0 to 5);
    if state(6) = '1' then
      next_state := next_state xor whitening_poly_c;
    end if;
    state := next_state;
  end procedure;

  procedure whitening_next(state: inout whitening_state_t;
                           w: out byte)
  is
    variable next_state : whitening_state_t;
    variable ret: byte;
    variable b: std_ulogic;
  begin
    next_state := state;
    for i in 0 to 7
    loop
      whitening_next(next_state, b);
      ret(i) := b;
    end loop;
    state := next_state;
    w := ret;
  end procedure;

  function whitened(data: byte_string;
                    init: whitening_state_t) return byte_string
  is
    alias xdata: byte_string(0 to data'length-1) is data;
    variable ret: byte_string(0 to data'length-1);
    variable wh: byte;
    variable state : whitening_state_t := init;
  begin
    for i in xdata'range
    loop
      whitening_next(state, wh);
      ret(i) := data(i) xor wh;
    end loop;
    return ret;
  end function;

end package body;
