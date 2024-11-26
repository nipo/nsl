library ieee, nsl_data;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use nsl_data.bytestream.all;

-- Text manipulation helpers
package text is

  -- Stringifiers, simpler to use than type'image()
  function to_string(v: in std_ulogic_vector) return string;
  function to_string(v: in std_logic_vector) return string;
  function to_string(v: in std_ulogic) return string;
  function to_string(v: in bit_vector) return string;
  function to_string(v: in real) return string;
  function to_string(v: in integer) return string;
  function to_string(v: in boolean) return string;
  function to_string(v: in unsigned) return string;
  function to_string(data : byte_string) return string;
  function to_string(data : byte_string;
                     mask: std_ulogic_vector;
                     masked_out_value: string(1 to 2)) return string;
  function to_string(value: time) return string;

  -- Hex stringifiers
  function to_hex_string(data : byte_string) return string;
  function to_hex_string(v: in std_ulogic_vector) return string;
  function to_hex_string(v: in std_logic_vector) return string;
  function to_hex_string(v: in bit_vector) return string;

  -- String ternary operation
  function if_else(v: boolean; a,b: string) return string;
  
  -- For a string composed of a space-separated collection of "token(params)"
  -- groups, return /params/ for a given token key.
  -- No spaces are allowed in params
  function str_param_extract(str, key: string) return string;
  
  -- Returns an index to add to haystack'left. If returns -1, needle
  -- is not found.
  function strchr(haystack : string;
                  needle : character;
                  start_index : integer := 0) return integer;
  -- Return index of substring
  function strstr(haystack, needle : string;
                  start_index : integer := 0) return integer;


  -- Search for needle, either at begin/end of string, or separated by
  -- separator.
  function strfind(haystack, needle : string;
                   separator : character) return boolean;
  -- Search for needle in haystack (like libc's strstr, with inverted
  -- response boolean value)
  function strfind(haystack, needle : string) return boolean;

  function "*"(s: string; n: natural) return string;
  
end package;

package body text is

  function to_string(v : in std_ulogic) return string is
  begin
    case v is
      when 'X' => return "X";
      when 'U' => return "U";
      when 'Z' => return "Z";
      when '0' => return "0";
      when '1' => return "1";
      when '-' => return "-";
      when 'W' => return "W";
      when 'H' => return "H";
      when 'L' => return "L";
      when others => return "0";
    end case;
  end function;    

  function to_string(v: in std_ulogic_vector) return string is
    alias xv: std_ulogic_vector(1 to v'length) is v;
    variable ret: string(1 to v'length);
  begin
    for i in xv'range loop
      ret(i to i) := to_string(xv(i));
    end loop;

    return ret;
  end function to_string;

  function to_string(v: in real) return string is
  begin
    return real'image(v);
  end function to_string;

  function to_string(v: in integer) return string is
  begin
    return integer'image(v);
  end function to_string;

  function to_string(v: in std_logic_vector) return string is
  begin
    return to_string(std_ulogic_vector(v));
  end function;

  function to_string(v: in bit_vector) return string is
  begin
    return to_string(to_stdulogicvector(v));
  end function;

  function to_string(data : byte_string) return string is
    alias xdata: byte_string(1 to data'length) is data;
    variable ret: string(1 to data'length * 3 + 1);
  begin
    if data'length = 0 then
      return "[]";
    end if;

    for i in xdata'range
    loop
      ret(i*3-2) := ' ';
      ret(i*3-1 to i*3) := to_hex_string(xdata(i));
    end loop;
    ret(ret'left) := '[';
    ret(ret'right) := ']';

    return ret;
  end function;

  function to_string(data : byte_string;
                     mask: std_ulogic_vector;
                     masked_out_value: string(1 to 2)) return string
  is
    alias xdata: byte_string(1 to data'length) is data;
    alias xmask: std_ulogic_vector(1 to mask'length) is mask;
    variable ret: string(1 to data'length * 3 + 1);
  begin
    if data'length = 0 then
      return "[]";
    end if;

    assert xdata'length = xmask'length
      report "Both arguments must have the same length"
      severity failure;

    for i in xdata'range
    loop
      ret(i*3-2) := ' ';
      if xmask(i) = '1' then
        ret(i*3-1 to i*3) := to_hex_string(xdata(i));
      else
        ret(i*3-1 to i*3) := masked_out_value;
      end if;
    end loop;
    ret(ret'left) := '[';
    ret(ret'right) := ']';

    return ret;
  end function;

  function to_string(v: in unsigned) return string
  is
  begin
    return "x""" & to_hex_string(std_ulogic_vector(v)) & """";
  end function;

  function to_hex_string(data : byte_string) return string is
    alias din : byte_string(0 to data'length-1) is data;
    variable ret : string(0 to data'length*2-1);
  begin
    for i in din'range
    loop
      ret(i*2 to i*2+1) := to_hex_string(std_ulogic_vector(din(i)));
    end loop;

    return ret;
  end function;

  function to_hex_string(v: in bit_vector) return string is
    variable ret: string(1 to (v'length + 3) / 4);
    constant pad : bit_vector(1 to ret'length*4 - v'length) := (others => '0');
    constant t : bit_vector(4  to ret'length*4+3) := pad & v;
    variable nibble : bit_vector(3 downto 0);
    variable c : character;
  begin
    for i in ret'range loop
      nibble := t(4 * i to 4 * i + 3);
      case nibble is
        when "0000" => c := '0';
        when "0001" => c := '1';
        when "0010" => c := '2';
        when "0011" => c := '3';
        when "0100" => c := '4';
        when "0101" => c := '5';
        when "0110" => c := '6';
        when "0111" => c := '7';
        when "1000" => c := '8';
        when "1001" => c := '9';
        when "1010" => c := 'a';
        when "1011" => c := 'b';
        when "1100" => c := 'c';
        when "1101" => c := 'd';
        when "1110" => c := 'e';
        when others => c := 'f';
      end case;
      ret(i) := c;
    end loop;

    return ret;
  end function;

  function to_hex_string(v: in std_ulogic_vector) return string is
    variable ret: string(1 to (v'length + 3) / 4);
    constant pad : std_ulogic_vector(1 to ret'length*4 - v'length) := (others => '0');
    constant t : std_ulogic_vector(4  to ret'length*4+3) := pad & v;
    variable nibble : std_ulogic_vector(3 downto 0);
    variable c : character;
  begin
    for i in ret'range loop
      nibble := t(4 * i to 4 * i + 3);
      case nibble is
        when "0000" => c := '0';
        when "0001" => c := '1';
        when "0010" => c := '2';
        when "0011" => c := '3';
        when "0100" => c := '4';
        when "0101" => c := '5';
        when "0110" => c := '6';
        when "0111" => c := '7';
        when "1000" => c := '8';
        when "1001" => c := '9';
        when "1010" => c := 'a';
        when "1011" => c := 'b';
        when "1100" => c := 'c';
        when "1101" => c := 'd';
        when "1110" => c := 'e';
        when "1111" => c := 'f';
        when "----" => c := '-';
        when "UUUU" => c := 'U';
        when others => c := 'X';
      end case;
      ret(i) := c;
    end loop;

    return ret;
  end function to_hex_string;

  function to_hex_string(v: in std_logic_vector) return string is
  begin
    return to_hex_string(std_ulogic_vector(v));
  end function;

  function to_string(v: in boolean) return string
  is
  begin
    if v then
      return "true";
    else
      return "false";
    end if;
  end function;

  function strchr(haystack : string;
                  needle : character;
                  start_index : integer := 0) return integer
  is
    alias h: string(0 to haystack'length-1) is haystack;
  begin
    if start_index >= h'length or start_index < 0 then
      return -1;
    end if;

    for offset in h'left + start_index to h'right
    loop
      if h(offset) = needle then
        return offset;
      end if;
    end loop;

    return -1;
  end function;

  function strstr(haystack, needle : string;
                  start_index : integer := 0) return integer
  is
    alias h: string(0 to haystack'length-1) is haystack;
    alias n: string(0 to needle'length-1) is needle;
  begin
    if n'length > h'length then
      return -1;
    end if;

    for offset in h'left to h'right - n'length + 1
    loop
      if h(offset to offset + n'length - 1) = n then
        return offset;
      end if;
    end loop;

    return -1;
  end function;

  function to_string(value: time) return string
  is
  begin
    return time'image(value);
  end function;

  function strfind(haystack, needle : string) return boolean
  is
  begin
    return strstr(haystack, needle) >= 0;
  end function;

  function strfind(haystack, needle : string;
                   separator : character) return boolean
  is
  begin
    return strfind(separator & haystack & separator, needle);
  end function;

  function str_param_extract(str, key: string)
    return string
  is
    constant tmp : string(1 to str'length + 2) := " " & str & " ";
    variable start, stop: integer;
  begin
    start := strstr(tmp, " "&key&"(");
    if start < 0 then
      return "";
    end if;

    stop := strstr(tmp, ") ", start + key'length + 2);
    if stop < 0 then
      return "";
    end if;

    return tmp(start + key'length + 2 to stop - 1);
  end function;

  function if_else(v: boolean; a,b: string) return string is
  begin
    if v then
      return a;
    else
      return b;
    end if;
  end function;

  function "*"(s: string; n: natural) return string is
    alias xs: string(1 to s'length) is s;
    variable ret : string(1 to xs'length*n);
  begin
    for i in 0 to n-1
    loop
      ret(i * xs'length + 1 to xs'length * (i + 1)) := xs;
    end loop;
    return ret;
  end function;
      

end package body;

