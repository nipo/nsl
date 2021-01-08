library ieee, nsl_data, nsl_math;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use nsl_data.bytestream.all;
use nsl_math.fixed.all;

package text is

  function to_string(v: in std_ulogic_vector) return string;
  function to_string(v: in std_logic_vector) return string;
  function to_string(v: in std_ulogic) return string;
  function to_string(v: in bit_vector) return string;
  function to_string(v: in real) return string;
  function to_string(v: in integer) return string;
  function to_string(v: in boolean) return string;
  function to_string(data : byte_string) return string;
  function to_string(value: sfixed) return string;
  function to_string(value: ufixed) return string;

  function to_hex_string(v: in std_ulogic_vector) return string;
  function to_hex_string(v: in std_logic_vector) return string;
  function to_hex_string(v: in bit_vector) return string;
  
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
    variable c: character;
    variable ret: line := new string'("");
  begin
    for i in v'range loop
      write(ret, to_string(v(i)));
    end loop;

    return ret.all;
  end function to_string;

  function to_string(v: in real) return string is
    variable ret: line := new string'("");
  begin
    write(ret, v);
    return ret.all;
  end function to_string;

  function to_string(v: in integer) return string is
    variable ret: line := new string'("");
  begin
    write(ret, v);
    return ret.all;
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
    variable ret : line := new string'("");
  begin
    write(ret, string'("["), left, 1);
    for i in data'range
    loop
      if i /= data'left then
        write(ret, string'(" "), left, 1);
      end if;
      write(ret, to_hex_string(data(i)), left, 2);
    end loop;
    write(ret, string'("]"), left, 1);

    return ret.all;
  end function;

  function to_hex_string(v: in bit_vector) return string is
    variable ret: string(1 to (v'length + 3) / 4);
    alias xv: bit_vector(4 to v'length+3) is v;
    variable t : bit_vector(4  to ret'length*4+3) := (others => '0');
    variable nibble : bit_vector(3 downto 0);
    variable c : character;
  begin
    t(xv'range) := xv;

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
  end function to_hex_string;

  function to_hex_string(v: in std_ulogic_vector) return string is
  begin
    return to_hex_string(to_bitvector(v));
  end function;

  function to_hex_string(v: in std_logic_vector) return string is
  begin
    return to_hex_string(to_bitvector(v));
  end function;

  function to_string(value: ufixed) return string
  is
    constant int : string := to_string(to_suv(value(value'left downto 0)));
    constant frac : string := to_string(to_suv(value(-1 downto value'right)));
  begin
    return int & "." & frac;
  end function;

  function to_string(value: sfixed) return string
  is
    constant int : string := to_string(to_suv(value(value'left downto 0)));
    constant frac : string := to_string(to_suv(value(-1 downto value'right)));
  begin
    return int & "." & frac;
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

end package body;

