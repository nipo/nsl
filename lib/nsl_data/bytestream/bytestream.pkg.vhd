library ieee;
use ieee.std_logic_1164.all;

package bytestream is

  subtype byte_hex_string is string(1 to 2);
  subtype byte is std_ulogic_vector(7 downto 0);
  type byte_string is array(natural range <>) of byte;

  function from_suv(blob: std_ulogic_vector) return byte_string;
  function byte_from_hex(blob: byte_hex_string) return byte;
  function from_hex(blob: string) return byte_string;
  
end package bytestream;

package body bytestream is

  function from_suv(blob: std_ulogic_vector) return byte_string is
    alias xblob : std_ulogic_vector(0 to blob'length - 1) is blob;
    variable ret : byte_string(0 to blob'length / 8 -1);
  begin
    assert
      (blob'length mod 8) = 0
      report "blob vector should be a multiple of 8 bits"
      severity failure;

    for i in ret'range
    loop
      ret(i) := xblob(i * 8 to i * 8 + 7);
    end loop;

    return ret;
  end function;

  function nibble_to_suv(nibble : character) return std_ulogic_vector is
  begin
    case nibble is
      when '0' => return x"0";
      when '1' => return x"1";
      when '2' => return x"2";
      when '3' => return x"3";
      when '4' => return x"4";
      when '5' => return x"5";
      when '6' => return x"6";
      when '7' => return x"7";
      when '8' => return x"8";
      when '9' => return x"9";
      when 'a'|'A' => return x"a";
      when 'b'|'B' => return x"b";
      when 'c'|'C' => return x"c";
      when 'd'|'D' => return x"d";
      when 'e'|'E' => return x"e";
      when 'f'|'F' => return x"f";
      when others => return "XXXX";
    end case;
  end function;

  function byte_from_hex(blob: byte_hex_string) return byte is
  begin
    return nibble_to_suv(blob(1)) & nibble_to_suv(blob(2));
  end function;

  function from_hex(blob: string) return byte_string is
    alias xblob : string(1 to blob'length) is blob;
    variable ret : byte_string(0 to blob'length / 2 -1);
  begin
    assert
      (blob'length mod 2) = 0
      report "blob vector should contain an even count of characters"
      severity failure;

    for i in ret'range
    loop
      ret(i) := byte_from_hex(blob(i * 2 + 1 to i * 2 + 2));
    end loop;

    return ret;
  end function;

end package body bytestream;