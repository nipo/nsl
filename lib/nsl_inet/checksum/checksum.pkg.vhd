library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

package checksum is

  subtype checksum_acc_t is signed(16 downto 0);
  subtype checksum_field_t is byte_string(0 to 1);

  constant checksum_acc_init_c : checksum_acc_t := "01111111111111111";

  function checksum_update(acc: checksum_acc_t; d: byte)
    return checksum_acc_t;

  function checksum_update(acc: checksum_acc_t; s: byte_string)
    return checksum_acc_t;

  function checksum_acc_is_valid(acc: checksum_acc_t) return boolean;

  function checksum_is_valid(data : byte_string) return boolean;

  function checksum_spill(acc: checksum_acc_t;
                          is_misaligned: boolean := false)
    return checksum_field_t;

end package;

package body checksum is

  function checksum_update(acc: checksum_acc_t; d: byte)
    return checksum_acc_t
  is
    variable a, b, ret: checksum_acc_t;
  begin
    a := "0" & acc(7 downto 0) & acc(15 downto 8);
    b := x"00" & acc(16) & signed(d);
    ret := a - b;
    return ret;
  end function;

  function checksum_update2(acc: checksum_acc_t; s: byte_string(0 to 1))
    return checksum_acc_t
  is
    variable a, b, ret: unsigned(16 downto 0);
    variable c: unsigned(0 downto 0);
  begin
    a := "0" & unsigned(acc(15 downto 0));
    b := not ("0" & unsigned(from_be(s)));
    c(0) := not acc(16);
    ret := a + b + c;
    return signed(ret);
  end function;    

  function checksum_update(acc: checksum_acc_t; s: byte_string)
    return checksum_acc_t
  is
    variable ret: checksum_acc_t := acc;
  begin
    if s'length = 2 then
      return checksum_update2(ret, s);
    end if;
    
    for i in s'range
    loop
      ret := checksum_update(ret, s(i));
    end loop;
    return ret;
  end function;    

  function checksum_acc_is_valid(acc: checksum_acc_t)
    return boolean
  is
  begin
    return acc = (acc'range => '1') or acc = (acc'range => '0');
  end function;

  function checksum_is_valid(data : byte_string)
    return boolean
  is
  begin
    return checksum_acc_is_valid(checksum_update(checksum_acc_init_c, data & x"00"));
  end function;

  function checksum_spill(acc: checksum_acc_t;
                          is_misaligned: boolean := false)
    return checksum_field_t
  is
    variable chk: checksum_acc_t := acc;
  begin
    if is_misaligned then
      chk := checksum_update(chk, to_byte(0));
    else
      chk := checksum_update2(chk, from_hex("0000"));
    end if;

    return to_be(unsigned(chk(15 downto 0)));
  end function;

end package body;
