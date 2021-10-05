library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tmds is

  type tmds_symbol_t is array(natural range 9 downto 0) of std_ulogic;
  
  -- DVI/HDMI TMDS encoder.
  component tmds_encoder is
    -- de_i  terc4_i control_i      pixel_i                        symbol_o
    --    1        0      XXXX   pixel data            TMDS_encode(pixel_i)
    --    0        0      -0VH            X              CONTROL_encode(VH)
    --    0        0      -100            X         HDMI guard "0100110011"
    --    0        0      -101            X         HDMI guard "1011001100"
    --    X        1   control            X         TERC4_encode(control_i)
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- If symbol is a normal pixel data, de_i should be asserted and pixel_i
      -- should be assigned to the pixel value.
      de_i : in std_ulogic;
      pixel_i : in  unsigned(7 downto 0);

      -- When de_i = 0, we encode a control word. Control may either be
      -- TERC4-encoded or a basic control word, depending on terc4_i value.
      terc4_i : in std_ulogic := '0';
      control_i : in std_ulogic_vector(3 downto 0);

      symbol_o : out tmds_symbol_t
      );
  end component;

  -- DVI/HDMI TMDS decoder.
  component tmds_decoder is
    --     symbol_i   de_o     pixel_o  terc4_o  control_o
    --      Control      0   undefined        0  CONTROL_decode(symbol)
    --   TERC4 data      1  TERC4 word        1    TERC4_decode(symbol)
    --   Pixel data      1       pixel        X                  "0000"
    --
    -- Note: HDMI guard symbols are decoded as pixel words:
    -- - 0100110011: 0x55
    -- - 1011001100: 0xab (also terc4 0x8)
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      symbol_i : in tmds_symbol_t;

      -- Either pixel data or a TERC4 encoded word is present
      -- de_o = 0 for control words, and 1 for TERC4 data.
      de_o : out std_ulogic;
      -- Pixel data
      pixel_o : out unsigned(7 downto 0);

      -- Symbol is a also a TERC4 data word
      terc4_o : out std_ulogic;
      -- Control / TERC4 data
      control_o : out std_ulogic_vector(3 downto 0)
      );
  end component;

  function terc4_encode(i: std_ulogic_vector(3 downto 0)) return tmds_symbol_t;
  function control_encode(i: std_ulogic_vector(2 downto 0)) return tmds_symbol_t;
  -- Returns 6 bits: [valid] [terc4] [code_x4]
  function control_decode(i: tmds_symbol_t) return std_ulogic_vector;

end package tmds;

package body tmds is

  function terc4_encode(i: std_ulogic_vector(3 downto 0)) return tmds_symbol_t
  is
  begin
    case i is
      when x"0"   => return "1010011100";
      when x"1"   => return "1001100011";
      when x"2"   => return "1011100100";
      when x"3"   => return "1011100010";
      when x"4"   => return "0101110001";
      when x"5"   => return "0100011110";
      when x"6"   => return "0110001110";
      when x"7"   => return "0100111100";
      when x"8"   => return "1011001100";
      when x"9"   => return "0100111001";
      when x"a"   => return "0110011100";
      when x"b"   => return "1011000110";
      when x"c"   => return "1010001110";
      when x"d"   => return "1001110001";
      when x"e"   => return "0101100011";
      when others => return "1011000011";
    end case;
  end function;

  -- Takes 3-bit input.
  -- When i(2) is 0, this is DVI control codes,
  -- When i(2) is 1, generate other HDMI control codes
  function control_encode(i: std_ulogic_vector(2 downto 0)) return tmds_symbol_t
  is
  begin
    case i is
      when "000"   => return "1101010100";
      when "001"   => return "0010101011";
      when "010"   => return "0101010100";
      when "011"   => return "1010101011";
      when "100"   => return "0100110011";
      when "101"   => return "1011001100";
      when others  => return "----------";
    end case;
  end function;

  function control_decode(i: tmds_symbol_t) return std_ulogic_vector
  is
  begin
    case i is
      when "1101010100" => return "10--00";
      when "0010101011" => return "10--01";
      when "0101010100" => return "10--10";
      when "1010101011" => return "10--11";
      when "1010011100" => return "11" & x"0";
      when "1001100011" => return "11" & x"1";
      when "1011100100" => return "11" & x"2";
      when "1011100010" => return "11" & x"3";
      when "0101110001" => return "11" & x"4";
      when "0100011110" => return "11" & x"5";
      when "0110001110" => return "11" & x"6";
      when "0100111100" => return "11" & x"7";
      when "1011001100" => return "11" & x"8";
      when "0100111001" => return "11" & x"9";
      when "0110011100" => return "11" & x"a";
      when "1011000110" => return "11" & x"b";
      when "1010001110" => return "11" & x"c";
      when "1001110001" => return "11" & x"d";
      when "0101100011" => return "11" & x"e";
      when "1011000011" => return "11" & x"f";
      when others => return "0-----";
    end case;
  end function;

end package body tmds;
