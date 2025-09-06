library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package seven_segment is

  subtype seven_segment_t is std_ulogic_vector(0 to 6);
  type seven_segment_vector is array (integer range <>) of seven_segment_t;

  function to_seven_segment(value: integer range 0 to 9) return seven_segment_t;
  function to_seven_segment(hex: unsigned(3 downto 0)) return seven_segment_t;
  function to_seven_segment(value: character) return seven_segment_t;
  
end package;

package body seven_segment is

  function to_seven_segment(value: integer range 0 to 9) return seven_segment_t
  is
  begin
    case value is
      when 0 => return "1111110";
      when 1 => return "0110000";
      when 2 => return "1101101";
      when 3 => return "1111001";
      when 4 => return "0110011";
      when 5 => return "1011011";
      when 6 => return "1011111";
      when 7 => return "1110000";
      when 8 => return "1111111";
      when 9 => return "1111011";
    end case;
  end function;

  function to_seven_segment(hex: unsigned(3 downto 0)) return seven_segment_t
  is
  begin
    case hex is
      when x"0" => return "1111110";
      when x"1" => return "0110000";
      when x"2" => return "1101101";
      when x"3" => return "1111001";
      when x"4" => return "0110011";
      when x"5" => return "1011011";
      when x"6" => return "1011111";
      when x"7" => return "1110000";
      when x"8" => return "1111111";
      when x"9" => return "1111011";
      when x"A" => return "1110111";
      when x"B" => return "0011111";
      when x"C" => return "1001110";
      when x"D" => return "0111101";
      when x"E" => return "1101111";
      when x"F" => return "1000111";
      when others => return "0000000";
    end case;
  end function;

  function to_seven_segment(value: character) return seven_segment_t
  is
  begin
    case value is
      when '_' => return "0001000";
      when '-' => return "0000001";
      when ''' => return "0100000";
      when '`' => return "0000010";
      when '/' => return "0100101";
      when '\' => return "0010011";
      when '|' => return "0000110";
      when '"' => return "0100010";
      when '0' => return "1111110";
      when '1' => return "0110000";
      when '2' => return "1101101";
      when '3' => return "1111001";
      when '4' => return "0110011";
      when '5' => return "1011011";
      when '6' => return "1011111";
      when '7' => return "1110000";
      when '8' => return "1111111";
      when '9' => return "1111011";
      when 'A'|'a' => return "1110111";
      when 'B'|'b' => return "0011111";
      when 'C'|'c' => return "1001110";
      when 'D'|'d' => return "0111101";
      when 'E'|'e' => return "1101111";
      when 'F'|'f' => return "1000111";
      when 'G'|'g' => return "1011111";
      when 'H'|'h' => return "0010111";
      when 'I'|'i' => return "0001100";
      when 'J'|'j' => return "1111100";
      when 'K'|'k' => return "0100111";
      when 'L'|'l' => return "0001110";
      when 'M'|'m' => return "1110110";
      when 'N'|'n' => return "0010101";
      when 'O'|'o' => return "0011101";
      when 'P'|'p' => return "1100111";
      when 'Q'|'q' => return "1110011";
      when 'R'|'r' => return "0000101";
      when 'S'|'s' => return "0011001";
      when 'T'|'t' => return "0001111";
      when 'U'|'u' => return "0011100";
      when 'V'|'v' => return "0111100";
      when 'W'|'w' => return "0111110";
      when 'X'|'x' => return "0110111";
      when 'Y'|'y' => return "0110011";
      when 'Z'|'z' => return "1111000";
      when others => return "0000000";
    end case;
  end function;

end package body;
