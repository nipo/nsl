library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package morse is

  subtype morse_character_t is std_ulogic_vector(7 downto 0);

  -- Encoding: From LSB to MSB, tah = 1, tee = 0, add 1 as marker for end of character
  -- Example:
  -- B = -... (tah tee tee tee)
  -- - encoding: "1000",
  -- - add "1" after code word: "10001",
  -- - padded to 8 bits: "00010001".
  -- - from LSB to MSB: "10001000".
  function character_encode(c: string) return morse_character_t;
  
  constant morse_a           : morse_character_t := character_encode(".-");
  constant morse_b           : morse_character_t := character_encode("-...");
  constant morse_c           : morse_character_t := character_encode("-.-.");
  constant morse_d           : morse_character_t := character_encode("-..");
  constant morse_e           : morse_character_t := character_encode(".");
  constant morse_f           : morse_character_t := character_encode("..-.");
  constant morse_g           : morse_character_t := character_encode("--.");
  constant morse_h           : morse_character_t := character_encode("....");
  constant morse_i           : morse_character_t := character_encode("..");
  constant morse_j           : morse_character_t := character_encode(".---");
  constant morse_k           : morse_character_t := character_encode("-.-");
  constant morse_l           : morse_character_t := character_encode(".-..");
  constant morse_m           : morse_character_t := character_encode("--");
  constant morse_n           : morse_character_t := character_encode("-.");
  constant morse_o           : morse_character_t := character_encode("---");
  constant morse_p           : morse_character_t := character_encode(".--.");
  constant morse_q           : morse_character_t := character_encode("--.-");
  constant morse_r           : morse_character_t := character_encode(".-.");
  constant morse_s           : morse_character_t := character_encode("...");
  constant morse_t           : morse_character_t := character_encode("-");
  constant morse_u           : morse_character_t := character_encode("..-");
  constant morse_v           : morse_character_t := character_encode("...-");
  constant morse_w           : morse_character_t := character_encode(".--");
  constant morse_x           : morse_character_t := character_encode("-..-");
  constant morse_y           : morse_character_t := character_encode("-.--");
  constant morse_z           : morse_character_t := character_encode("--..");
  constant morse_0           : morse_character_t := character_encode("-----");
  constant morse_1           : morse_character_t := character_encode(".----");
  constant morse_2           : morse_character_t := character_encode("..---");
  constant morse_3           : morse_character_t := character_encode("...--");
  constant morse_4           : morse_character_t := character_encode("....-");
  constant morse_5           : morse_character_t := character_encode(".....");
  constant morse_6           : morse_character_t := character_encode("-....");
  constant morse_7           : morse_character_t := character_encode("--...");
  constant morse_8           : morse_character_t := character_encode("---..");
  constant morse_9           : morse_character_t := character_encode("----.");
  constant morse_dot         : morse_character_t := character_encode(".-.-.-");
  constant morse_comma       : morse_character_t := character_encode("--..--");
  constant morse_question    : morse_character_t := character_encode("..--..");
  constant morse_quote       : morse_character_t := character_encode(".----.");
  -- unsupported for now, too long
  --constant morse_bang        : morse_character_t := character_encode("-.-.-----.");
  constant morse_slash       : morse_character_t := character_encode("-..-.");
  constant morse_paren_open  : morse_character_t := character_encode("-.--.");
  constant morse_paren_close : morse_character_t := character_encode("-.--.-");
  constant morse_amp         : morse_character_t := character_encode(".-...");
  constant morse_colon       : morse_character_t := character_encode("---...");
  constant morse_semicolon   : morse_character_t := character_encode("-.-.-.");
  constant morse_equal       : morse_character_t := character_encode("-...-");
  constant morse_plus        : morse_character_t := character_encode(".-.-.");
  constant morse_dash        : morse_character_t := character_encode("-....-");
  constant morse_underscore  : morse_character_t := character_encode("..--.-");
  constant morse_doublequote : morse_character_t := character_encode(".-..-.");
  constant morse_dollar      : morse_character_t := character_encode("...-..-");
  constant morse_at          : morse_character_t := character_encode(".--.-.");

  type morse_string is array(positive range <>) of morse_character_t;
  
  -- Tee is always encoded as 1 symbol time,
  -- Tah is always encoded as 3 symbol time,
  -- Inter-symbol is encoded as 1 duration,
  -- Inter-character and inter-word as selectable.
  component morse_encoder
    generic (
      -- clock_i frequency (hz)
      clock_rate_c : positive;
      -- Normalized symbol rate is 512
      symbol_per_minute_c : positive := 512;
      -- inter-character duration, in symbol time
      inter_character_duration_c : positive := 3;
      -- inter-word duration, in symbol time
      inter_word_duration_c : positive := 7
      );
    port (
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      valid_i : in std_ulogic;
      -- Marks character as last one, i.e. inserts an inter-word pause after
      -- this character.
      last_i : in std_ulogic;
      ready_o : out std_ulogic;
      data_i : in morse_character_t;

      -- '1' when beep.
      morse_o : out std_ulogic
      );
  end component;

end package morse;

package body morse is

  function character_encode(c: string) return morse_character_t
  is
    alias xc : string (1 to c'length) is c;
    variable ret : morse_character_t := (others => '0');
  begin
    assert c'length <= 7
       report "Character too long"
       severity failure;
    for i in 0 to c'length-1
    loop
      if xc(1+i) = '-' then
        ret(i) := '1';
      end if;
    end loop;
    ret(c'length) := '1';

    return ret;
  end function;
    
end package body;
