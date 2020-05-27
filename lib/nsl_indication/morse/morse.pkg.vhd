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
  
  constant morse_a           : morse_character_t := "00000110";  -- .-
  constant morse_b           : morse_character_t := "00010001";  -- -...
  constant morse_c           : morse_character_t := "00010101";  -- -.-.
  constant morse_d           : morse_character_t := "00000001";  -- -..
  constant morse_e           : morse_character_t := "00000010";  -- .
  constant morse_f           : morse_character_t := "00010100";  -- ..-.
  constant morse_g           : morse_character_t := "00001110";  -- --.
  constant morse_h           : morse_character_t := "00010000";  -- ....
  constant morse_i           : morse_character_t := "00000100";  -- ..
  constant morse_j           : morse_character_t := "00011110";  -- .---
  constant morse_k           : morse_character_t := "00001101";  -- -.-
  constant morse_l           : morse_character_t := "00010010";  -- .-..
  constant morse_m           : morse_character_t := "00000111";  -- --
  constant morse_n           : morse_character_t := "00000101";  -- -.
  constant morse_o           : morse_character_t := "00001111";  -- ---
  constant morse_p           : morse_character_t := "00010110";  -- .--.
  constant morse_q           : morse_character_t := "00011011";  -- --.-
  constant morse_r           : morse_character_t := "00001010";  -- .-.
  constant morse_s           : morse_character_t := "00001000";  -- ...
  constant morse_t           : morse_character_t := "00000011";  -- -
  constant morse_u           : morse_character_t := "00001100";  -- ..-
  constant morse_v           : morse_character_t := "00011000";  -- ...-
  constant morse_w           : morse_character_t := "00001110";  -- .--
  constant morse_x           : morse_character_t := "00011001";  -- -..-
  constant morse_y           : morse_character_t := "00011101";  -- -.--
  constant morse_z           : morse_character_t := "00010011";  -- --..
  constant morse_0           : morse_character_t := "00111111";  -- -----
  constant morse_1           : morse_character_t := "00111110";  -- .----
  constant morse_2           : morse_character_t := "00111100";  -- ..---
  constant morse_3           : morse_character_t := "00111000";  -- ...--
  constant morse_4           : morse_character_t := "00110000";  -- ....-
  constant morse_5           : morse_character_t := "00100000";  -- .....
  constant morse_6           : morse_character_t := "00100001";  -- -....
  constant morse_7           : morse_character_t := "00100011";  -- --...
  constant morse_8           : morse_character_t := "00100111";  -- ---..
  constant morse_9           : morse_character_t := "00101111";  -- ----.
  constant morse_dot         : morse_character_t := "01101010";  -- .-.-.-
  constant morse_comma       : morse_character_t := "01110011";  -- --..--
  constant morse_question    : morse_character_t := "01001100";  -- ..--..
  constant morse_quote       : morse_character_t := "01011110";  -- .----.
  -- unsupported for now, too long
  --constant morse_bang        : morse_character_t := "";  -- -.-.-----.
  constant morse_slash       : morse_character_t := "00101001";  -- -..-.
  constant morse_paren_open  : morse_character_t := "00101101";  -- -.--.
  constant morse_paren_close : morse_character_t := "01101101";  -- -.--.-
  constant morse_amp         : morse_character_t := "00100010";  -- .-...
  constant morse_colon       : morse_character_t := "01000111";  -- ---...
  constant morse_semicolon   : morse_character_t := "01010101";  -- -.-.-.
  constant morse_equal       : morse_character_t := "00110001";  -- -...-
  constant morse_plus        : morse_character_t := "00101010";  -- .-.-.
  constant morse_dash        : morse_character_t := "00100001";  -- -....-
  constant morse_underscore  : morse_character_t := "01101100";  -- ..--.-
  constant morse_doublequote : morse_character_t := "01010010";  -- .-..-.
  constant morse_dollar      : morse_character_t := "11001000";  -- ...-..-
  constant morse_at          : morse_character_t := "01010110";  -- .--.-.

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
