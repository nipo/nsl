library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_data;
use nsl_data.bytestream.all;
use nsl_logic.logic.all;
use work.ibm_8b10b.all;

-- 8b/10b codec implemented from look-up tables. This is mostly
-- suitable for filling constants in a ROM-based codec.
package ibm_8b10b_table is

  procedure encode(
    data_i : in data_t;
    disparity_i : in std_ulogic;

    data_o : out code_word_t;
    disparity_o : out std_ulogic);

  -- Lookup decoding parameters for a given received word.
  --
  -- Disparity error and code error are dependent on current running
  -- disparity, which is not handled by this procedure.
  --
  -- Disparity_toggle_o tells whether the current word has uneven disparity.
  --
  -- Control decoding and RD toggle is RD-agnostic.
  --
  -- If you assume a single-bit error, RD should be toggled in
  -- addition to normal toggle if a disparity error is detected.
  --
  -- See decode() for example usage.
  procedure decode_lookup(
    data_i : in code_word_t;
    data_o : out data_t;
    disparity_error_o : out std_ulogic_vector(0 to 1);
    code_error_o : out std_ulogic_vector(0 to 1);
    disparity_toggle_o : out std_ulogic);

  -- Decode depending on received word and current disparity.
  procedure decode(
    data_i : in code_word_t;
    disparity_i : in std_ulogic;
    data_o : out data_t;
    disparity_o, code_error_o, disparity_error_o : out std_ulogic);

end package;

package body ibm_8b10b_table is

  constant enc_lut_data_0 : std_ulogic_vector(0 to 1023) := ""
    & "1011110111010100010101011101010110111101110101000101010111010101"
    & "1011110111010100010101011101010110111101110101000101010111010101"
    & "1011110111010100010101011101010110111101110101000101010111010101"
    & "1011110111010100010101011101010110111101110101000101010111010101"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------1---1010-"
    & "0101010001010101110101000100001001010100010101011101010001000010"
    & "0101010001010101110101000100001001010100010101011101010001000010"
    & "0101010001010101110101000100001001010100010101011101010001000010"
    & "0101010001010101110101000100001001010100010101011101010001000010"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------0---0101-";
  constant enc_lut_data_1 : std_ulogic_vector(0 to 1023) := ""
    & "0101101110110011101100111011001001011011101100111011001110110010"
    & "0101101110110011101100111011001001011011101100111011001110110010"
    & "0101101110110011101100111011001001011011101100111011001110110010"
    & "0101101110110011101100111011001001011011101100111011001110110010"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------1---1001-"
    & "1011001000110010001100100010010110110010001100100011001000100101"
    & "1011001000110010001100100010010110110010001100100011001000100101"
    & "1011001000110010001100100010010110110010001100100011001000100101"
    & "1011001000110010001100100010010110110010001100100011001000100101"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------0---0110-";
  constant enc_lut_data_2 : std_ulogic_vector(0 to 1023) := ""
    & "0110011110001110100011110000111101100111100011101000111100001111"
    & "0110011110001110100011110000111101100111100011101000111100001111"
    & "0110011110001110100011110000111101100111100011101000111100001111"
    & "0110011110001110100011110000111101100111100011101000111100001111"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------1---0111-"
    & "1000111000001111000011101001100010001110000011110000111010011000"
    & "1000111000001111000011101001100010001110000011110000111010011000"
    & "1000111000001111000011101001100010001110000011110000111010011000"
    & "1000111000001111000011101001100010001110000011110000111010011000"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------0---1000-";
  constant enc_lut_data_3 : std_ulogic_vector(0 to 1023) := ""
    & "1110100001111111000000000111111011101000011111110000000001111110"
    & "1110100001111111000000000111111011101000011111110000000001111110"
    & "1110100001111111000000000111111011101000011111110000000001111110"
    & "1110100001111111000000000111111011101000011111110000000001111110"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------0---1111-"
    & "0000000111111110100000011110100100000001111111101000000111101001"
    & "0000000111111110100000011110100100000001111111101000000111101001"
    & "0000000111111110100000011110100100000001111111101000000111101001"
    & "0000000111111110100000011110100100000001111111101000000111101001"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------1---0000-";
  constant enc_lut_data_4 : std_ulogic_vector(0 to 1023) := ""
    & "1000000000000001111111111111111110000000000000011111111111111111"
    & "1000000000000001111111111111111110000000000000011111111111111111"
    & "1000000000000001111111111111111110000000000000011111111111111111"
    & "1000000000000001111111111111111110000000000000011111111111111111"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------1---1111-"
    & "0110100110000000011111100110100001101001100000000111111001101000"
    & "0110100110000000011111100110100001101001100000000111111001101000"
    & "0110100110000000011111100110100001101001100000000111111001101000"
    & "0110100110000000011111100110100001101001100000000111111001101000"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------0---0000-";
  constant enc_lut_data_5 : std_ulogic_vector(0 to 1023) := ""
    & "1111111011101001111010001000000111111110111010011110100010000001"
    & "1111111011101001111010001000000111111110111010011110100010000001"
    & "1111111011101001111010001000000111111110111010011110100010000001"
    & "1111111011101001111010001000000111111110111010011110100010000001"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------0---0100-"
    & "0001011101101000011010010001011000010111011010000110100100010110"
    & "0001011101101000011010010001011000010111011010000110100100010110"
    & "0001011101101000011010010001011000010111011010000110100100010110"
    & "0001011101101000011010010001011000010111011010000110100100010110"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------1---1011-";
  constant enc_lut_data_6 : std_ulogic_vector(0 to 1023) := ""
    & "0001011101111110011111100110100011111111111111111111111111111111"
    & "0000000000000000000000000000000000010111011111100111111001101000"
    & "0001011101111110011111100110100011111111111111111111111111111111"
    & "0000000000000000000000000000000000010111011111100001011001101000"
    & "----------------------------0-------------------------------1---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------1---"
    & "----------------------------0--------------------------1---1111-"
    & "1110100010000001100000011001011111111111111111111111111111111111"
    & "0000000000000000000000000000000011101000100000011000000110010111"
    & "1110100010000001100000011001011111111111111111111111111111111111"
    & "0000000000000000000000000000000011101000100101111000000110010111"
    & "----------------------------1-------------------------------0---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------0---"
    & "----------------------------1--------------------------0---0000-";
  constant enc_lut_data_7 : std_ulogic_vector(0 to 1023) := ""
    & "1110100010000001100000011001011100000000000000000000000000000000"
    & "1111111111111111111111111111111100010111011111100111111001101000"
    & "0001011101111110011111100110100000000000000000000000000000000000"
    & "1111111111111111111111111111111100010111011111100111111001101000"
    & "----------------------------1-------------------------------0---"
    & "----------------------------1-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------1--------------------------0---0000-"
    & "0001011101111110011111100110100000000000000000000000000000000000"
    & "1111111111111111111111111111111111101000100000011000000110010111"
    & "1110100010000001100000011001011100000000000000000000000000000000"
    & "1111111111111111111111111111111111101000100000011000000110010111"
    & "----------------------------0-------------------------------1---"
    & "----------------------------0-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------0--------------------------1---1111-";
  constant enc_lut_data_8 : std_ulogic_vector(0 to 1023) := ""
    & "0001011101111110011111100110100000000000000000000000000000000000"
    & "0000000000000000000000000000000011101000100000011000000110010111"
    & "1110100010000001100000011001011111111111111111111111111111111111"
    & "1111111111111111111111111111111100010111011111100111111001101000"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------0---0000-"
    & "1110100010000001100000011001011100000000000000000000000000000000"
    & "0000000000000000000000000000000000010111011111100111111001101000"
    & "0001011101111110011111100110100011111111111111111111111111111111"
    & "1111111111111111111111111111111111101000100000011000000110010111"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------1---1111-";
  constant enc_lut_data_9 : std_ulogic_vector(0 to 1023) := ""
    & "0001011101111110011111100110100011111111111111111111111111111111"
    & "1111111111111111111111111111111111101000100000011000000110010111"
    & "0001011101111110011111100110100000000000000000000000000000000000"
    & "0000000000000000000000000000000011101000100000011110100110010111"
    & "----------------------------0-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------0--------------------------0---0000-"
    & "1110100010000001100000011001011111111111111111111111111111111111"
    & "1111111111111111111111111111111100010111011111100111111001101000"
    & "1110100010000001100000011001011100000000000000000000000000000000"
    & "0000000000000000000000000000000000010111011010000111111001101000"
    & "----------------------------1-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------1--------------------------1---1111-";
  constant enc_lut_rd : std_ulogic_vector(0 to 1023) := ""
    & "0001011101111110011111100110100011101000100000011000000110010111"
    & "1110100010000001100000011001011111101000100000011000000110010111"
    & "0001011101111110011111100110100011101000100000011000000110010111"
    & "1110100010000001100000011001011100010111011111100111111001101000"
    & "----------------------------0-------------------------------1---"
    & "----------------------------1-------------------------------1---"
    & "----------------------------0-------------------------------1---"
    & "----------------------------1--------------------------0---0000-"
    & "1110100010000001100000011001011100010111011111100111111001101000"
    & "0001011101111110011111100110100000010111011111100111111001101000"
    & "1110100010000001100000011001011100010111011111100111111001101000"
    & "0001011101111110011111100110100011101000100000011000000110010111"
    & "----------------------------1-------------------------------0---"
    & "----------------------------0-------------------------------0---"
    & "----------------------------1-------------------------------0---"
    & "----------------------------0--------------------------1---1111-";
  constant dec_lut_data_0 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-10--------1---1-10-----------------------------0---"
    & "-----------1-10----1-101-101010----1-100-100001--100010-101-0---"
    & "---0-101-011010--101010-010-0----011110-110-0----10-0-----------"
    & "-----------1-10----1-101-101010----1-100-100001--100010-101-0---"
    & "---0-101-011010--10101010101010--01111001100001--100010-101-0---"
    & "---0-101-011010--10101010101010--01111001100001--100010-101-0---"
    & "-----101-011010--101010-010-0----011110-110-0-------------------"
    & "-------------------1-101-101010----1-100-100001--100010-101-----"
    & "---0-101-011010--10101010101010--01111001100001--100010-101-0---"
    & "---0-101-011010--10101010101010--01111001100001--100010-101-0---"
    & "---0-101-011010--101010-010-0----011110-110-0----10-0-----------"
    & "-----------1-10----1-101-101010----1-100-100001--100010-101-0---"
    & "---0-101-011010--101010-010-0----011110-110-0----10-0-----------"
    & "---0-----------------------------01-1---1--------10-0-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_1 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-01--------1---1-01-----------------------------0---"
    & "-----------1-01----1-011-011001----1-010-010010--010010-101-0---"
    & "---0-101-011001--011001-001-0----101101-101-0----01-0-----------"
    & "-----------1-01----1-011-011001----1-010-010010--010010-101-0---"
    & "---0-101-011001--01100110011001--10110101010010--010010-101-0---"
    & "---0-101-011001--01100110011001--10110101010010--010010-101-0---"
    & "-----101-011001--011001-001-0----101101-101-0-------------------"
    & "-------------------1-011-011001----1-010-010010--010010-101-----"
    & "---0-101-011001--01100110011001--10110101010010--010010-101-0---"
    & "---0-101-011001--01100110011001--10110101010010--010010-101-0---"
    & "---0-101-011001--011001-001-0----101101-101-0----01-0-----------"
    & "-----------1-01----1-011-011001----1-010-010010--010010-101-0---"
    & "---0-101-011001--011001-001-0----101101-101-0----01-0-----------"
    & "---0-----------------------------10-1---1--------01-0-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_2 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------0-11--------1---0-11-----------------------------1---"
    & "-----------0-11----0-111-000111----0-110-001100--000110-101-1---"
    & "---1-101-010011--000111-000-1----110011-100-1----00-1-----------"
    & "-----------0-11----0-111-000111----0-110-001100--000110-101-1---"
    & "---1-101-010011--00011110000111--11001101001100--000110-101-1---"
    & "---1-101-010011--00011110000111--11001101001100--000110-101-1---"
    & "-----101-010011--000111-000-1----110011-100-1-------------------"
    & "-------------------0-111-000111----0-110-001100--000110-101-----"
    & "---1-101-010011--00011110000111--11001101001100--000110-101-1---"
    & "---1-101-010011--00011110000111--11001101001100--000110-101-1---"
    & "---1-101-010011--000111-000-1----110011-100-1----00-1-----------"
    & "-----------0-11----0-111-000111----0-110-001100--000110-101-1---"
    & "---1-101-010011--000111-000-1----110011-100-1----00-1-----------"
    & "---1-----------------------------11-0---1--------00-1-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_3 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-11--------0---1-11-----------------------------1---"
    & "-----------1-11----0-000-111111----0-001-110100--001010-001-1---"
    & "---1-100-011111--000000-111-1----110100-011-1----00-0-----------"
    & "-----------1-11----0-000-111111----0-001-110100--001010-001-1---"
    & "---1-100-011111--00000001111111--11010010110100--001010-001-1---"
    & "---1-100-011111--00000001111111--11010010110100--001010-001-1---"
    & "-----100-011111--000000-111-1----110100-011-1-------------------"
    & "-------------------0-000-111111----0-001-110100--001010-001-----"
    & "---1-100-011111--00000001111111--11010010110100--001010-001-1---"
    & "---1-100-011111--00000001111111--11010010110100--001010-001-1---"
    & "---1-100-011111--000000-111-1----110100-011-1----00-0-----------"
    & "-----------1-11----0-000-111111----0-001-110100--001010-001-1---"
    & "---1-100-011111--000000-111-1----110100-011-1----00-0-----------"
    & "---1-----------------------------11-1---0--------00-0-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_4 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------0-00--------1---1-11-----------------------------1---"
    & "-----------0-00----1-111-111111----0-000-000000--111111-000-1---"
    & "---1-000-110100--001011-011-1----110100-100-0----11-1-----------"
    & "-----------0-00----1-111-111111----0-000-000000--111111-000-1---"
    & "---1-000-110100--00101110111111--11010001000000--111111-000-1---"
    & "---1-000-110100--00101110111111--11010001000000--111111-000-1---"
    & "-----000-110100--001011-011-1----110100-100-0-------------------"
    & "-------------------1-111-111111----0-000-000000--111111-000-----"
    & "---1-000-110100--00101110111111--11010001000000--111111-000-1---"
    & "---1-000-110100--00101110111111--11010001000000--111111-000-1---"
    & "---1-000-110100--001011-011-1----110100-100-0----11-1-----------"
    & "-----------0-00----1-111-111111----0-000-000000--111111-000-1---"
    & "---1-000-110100--001011-011-1----110100-100-0----11-1-----------"
    & "---1-----------------------------11-1---1--------11-1-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_5 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-11--------1---1-11-----------------------------1---"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-0---"
    & "---1-111-111111--111111-111-1----111111-111-1----11-1-----------"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-0---"
    & "---0-111-111111--11111111111111--11111111111111--111111-111-1---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-0---"
    & "-----111-111111--111111-111-1----111111-111-1-------------------"
    & "-------------------1-111-111111----1-111-111111--111111-111-----"
    & "---0-111-111111--11111111111111--11111111111111--111111-111-1---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-0---"
    & "---0-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "-----------1-11----1-111-111111----1-111-111111--111111-111-1---"
    & "---0-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "---1-----------------------------11-1---1--------11-1-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_6 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-11--------1---1-11-----------------------------1---"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-0---"
    & "---1-111-111111--111111-111-1----111111-111-1----11-1-----------"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-0---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-0---"
    & "---0-111-111111--11111111111111--11111111111111--111111-111-1---"
    & "-----111-111111--111111-111-1----111111-111-1-------------------"
    & "-------------------1-111-111111----1-111-111111--111111-111-----"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-0---"
    & "---0-111-111111--11111111111111--11111111111111--111111-111-1---"
    & "---0-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "-----------1-11----1-111-111111----1-111-111111--111111-111-1---"
    & "---0-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "---1-----------------------------11-1---1--------11-1-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_data_7 : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-11--------1---1-11-----------------------------1---"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-0---"
    & "---0-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "-----------1-11----1-111-111111----1-111-111111--111111-111-1---"
    & "---0-111-111111--11111111111111--11111111111111--111111-111-1---"
    & "---0-111-111111--11111111111111--11111111111111--111111-111-1---"
    & "-----111-111111--111111-111-1----111111-111-1-------------------"
    & "-------------------1-111-111111----1-111-111111--111111-111-----"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-0---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-0---"
    & "---1-111-111111--111111-111-1----111111-111-1----11-1-----------"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-0---"
    & "---0-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "---1-----------------------------11-1---1--------11-1-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_k : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------0-00--------1---1-11-----------------------------1---"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-1---"
    & "---1-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-1---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-1---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-1---"
    & "-----000-000000--000000-000-0----000000-000-0-------------------"
    & "-------------------0-000-000000----0-000-000000--000000-000-----"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-1---"
    & "---1-000-000000--00000000000000--00000000000000--000000-000-1---"
    & "---1-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "-----------0-00----0-000-000000----0-000-000000--000000-000-1---"
    & "---1-000-000000--000000-000-0----000000-000-0----00-0-----------"
    & "---1-----------------------------11-1---1--------00-0-----------"
    & "----------------------------------------------------------------";
  constant dec_lut_err0 : std_ulogic_vector(0 to 1023) := ""
    & "1111111111111111111111111111111111111111111111111111111111111111"
    & "1111111111111111111111101110100111111111111111111111111111110111"
    & "1111111111111111111111101110100111111110111010011110100110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111111111111101110100111111110111010011110100110010111"
    & "1111111011101001111010001000000111101000100000011000000110010111"
    & "1111111011101001111010001000000111101000100000011000000110010111"
    & "1111111011101001111010011001011111101001100101111111111111111111"
    & "1111111111111111111111101110100111111110111010011110100110011111"
    & "1111111011101001111010001000000111101000100000011000000110010111"
    & "1111111011101001111010001000000111101000100000011000000110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111111111111101110100111111110111010011110100110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111111111111111111111111111111111111111001011111111111"
    & "1111111111111111111111111111111111111111111111111111111111111111";
  constant dec_lut_err1 : std_ulogic_vector(0 to 1023) := ""
    & "1111111111111111111111111111111111111111111111111111111111111111"
    & "1111111111101001111111111111111111111111111111111111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110010111100101110111111110010111011111111111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110000001100000010001011110000001000101111001011101111111"
    & "1110100110000001100000010001011110000001000101111001011101111111"
    & "1111100110010111100101110111111110010111011111111111111111111111"
    & "1111111111111111111010011001011111101001100101111001011101111111"
    & "1110100110000001100000010001011110000001000101111001011101111111"
    & "1110100110000001100000010001011110000001000101111001011101111111"
    & "1110100110010111100101110111111110010111011111111111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110010111100101110111111110010111011111111111111111111111"
    & "1110111111111111111111111111111110010111011111111111111111111111"
    & "1111111111111111111111111111111111111111111111111111111111111111";
  constant dec_lut_rderr0 : std_ulogic_vector(0 to 1023) := ""
    & "1111111111111111111111111111111111111111111111111111111111111111"
    & "1111111111111110111111101110100111111110111010011110100110010111"
    & "1111111111111110111111101110100111111110111010011110100110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111110111111101110100111111110111010011110100110010111"
    & "1111111011101000111010001000000111101000100000011000000110010111"
    & "1111111011101000111010001000000111101000100000011000000110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111110111111101110100111111110111010011110100110010111"
    & "1111111011101000111010001000000111101000100000011000000110010111"
    & "1111111011101000111010001000000111101000100000011000000110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111110111111101110100111111110111010011110100110010111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111011101001111010011001011111101001100101111001011111111111"
    & "1111111111111111111111111111111111111111111111111111111111111111";
  constant dec_lut_rderr1 : std_ulogic_vector(0 to 1023) := ""
    & "1111111111111111111111111111111111111111111111111111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110010111100101110111111110010111011111110111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110000001100000010001011110000001000101110001011101111111"
    & "1110100110000001100000010001011110000001000101110001011101111111"
    & "1110100110010111100101110111111110010111011111110111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110000001100000010001011110000001000101110001011101111111"
    & "1110100110000001100000010001011110000001000101110001011101111111"
    & "1110100110010111100101110111111110010111011111110111111111111111"
    & "1111111111101001111010011001011111101001100101111001011101111111"
    & "1110100110010111100101110111111110010111011111110111111111111111"
    & "1110100110010111100101110111111110010111011111110111111111111111"
    & "1111111111111111111111111111111111111111111111111111111111111111";
  constant dec_lut_rd_swap : std_ulogic_vector(0 to 1023) := ""
    & "----------------------------------------------------------------"
    & "-----------1-11--------0---0-00-----------------------------0---"
    & "-----------1-11----1-110-110100----1-110-110100--110100-100-0---"
    & "---1-110-110100--110100-100-0----110100-100-0----00-0-----------"
    & "-----------1-11----1-110-110100----1-110-110100--110100-100-0---"
    & "---1-110-110100--11010011001011--11010011001011--001011-011-1---"
    & "---1-110-110100--11010011001011--11010011001011--001011-011-1---"
    & "-----001-001011--001011-011-1----001011-011-1-------------------"
    & "-------------------1-110-110100----1-110-110100--110100-100-----"
    & "---1-110-110100--11010011001011--11010011001011--001011-011-1---"
    & "---1-110-110100--11010011001011--11010011001011--001011-011-1---"
    & "---0-001-001011--001011-011-1----001011-011-1----11-1-----------"
    & "-----------0-00----0-001-001011----0-001-001011--001011-011-1---"
    & "---0-001-001011--001011-011-1----001011-011-1----11-1-----------"
    & "---0-----------------------------00-0---0--------11-1-----------"
    & "----------------------------------------------------------------";

  function bit_lookup(lut, key: std_ulogic_vector) return std_ulogic
  is
  begin
    assert lut'length = 2 ** key'length
      report "Bad LUT/Key length match"
      severity failure;

    return lut(to_integer(unsigned(key)));
  end function;
  
  procedure encode(
    data_i : in data_t;
    disparity_i : in std_ulogic;
    data_o : out code_word_t;
    disparity_o : out std_ulogic)
  is
    constant key : std_ulogic_vector(9 downto 0) := disparity_i & data_i.control & data_i.data;
  begin
    data_o(0) := bit_lookup(enc_lut_data_0, key);
    data_o(1) := bit_lookup(enc_lut_data_1, key);
    data_o(2) := bit_lookup(enc_lut_data_2, key);
    data_o(3) := bit_lookup(enc_lut_data_3, key);
    data_o(4) := bit_lookup(enc_lut_data_4, key);
    data_o(5) := bit_lookup(enc_lut_data_5, key);
    data_o(6) := bit_lookup(enc_lut_data_6, key);
    data_o(7) := bit_lookup(enc_lut_data_7, key);
    data_o(8) := bit_lookup(enc_lut_data_8, key);
    data_o(9) := bit_lookup(enc_lut_data_9, key);
    disparity_o := bit_lookup(enc_lut_rd, key);
  end procedure;

  procedure decode_lookup(
    data_i : in code_word_t;
    data_o : out data_t;
    disparity_error_o : out std_ulogic_vector(0 to 1);
    code_error_o : out std_ulogic_vector(0 to 1);
    disparity_toggle_o : out std_ulogic)
  is
    constant key : std_ulogic_vector(9 downto 0) := data_i;
  begin
    data_o.data(0) := bit_lookup(dec_lut_data_0, key);
    data_o.data(1) := bit_lookup(dec_lut_data_1, key);
    data_o.data(2) := bit_lookup(dec_lut_data_2, key);
    data_o.data(3) := bit_lookup(dec_lut_data_3, key);
    data_o.data(4) := bit_lookup(dec_lut_data_4, key);
    data_o.data(5) := bit_lookup(dec_lut_data_5, key);
    data_o.data(6) := bit_lookup(dec_lut_data_6, key);
    data_o.data(7) := bit_lookup(dec_lut_data_7, key);
    code_error_o(0) := bit_lookup(dec_lut_err0, key);
    disparity_error_o(0) := bit_lookup(dec_lut_rderr0, key);
    code_error_o(1) := bit_lookup(dec_lut_err1, key);
    disparity_error_o(1) := bit_lookup(dec_lut_rderr1, key);
    data_o.control := bit_lookup(dec_lut_k, key);
    disparity_toggle_o := bit_lookup(dec_lut_rd_swap, key);
  end procedure;

  procedure decode(
    data_i : in code_word_t;
    disparity_i : in std_ulogic;
    data_o : out data_t;
    disparity_o, code_error_o, disparity_error_o : out std_ulogic)
  is
    constant key : std_ulogic_vector(9 downto 0) := data_i;
    variable disparity_error, code_error : std_ulogic_vector(0 to 1);
    variable disparity_toggle, control : std_ulogic;
    variable data: byte;
  begin
    decode_lookup(data_i, data_o,
                  disparity_error, code_error,
                  disparity_toggle);

    if disparity_i = '0' then
      code_error_o := code_error(0);
      disparity_error_o := disparity_error(0);
      disparity_o := (disparity_toggle xor disparity_i) and not disparity_error(0);
    else
      code_error_o := code_error(1);
      disparity_error_o := disparity_error(1);
      disparity_o := (disparity_toggle xor disparity_i) and not disparity_error(1);
    end if;
  end procedure;

end package body;
