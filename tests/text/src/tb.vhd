library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.text.all;
use nsl_simulation.assertions.all;

entity tb is
end tb;

architecture arch of tb is
begin

  Test0: process
    constant v_asc_b : bit_vector(0 to 15) := X"1234";
    constant v_asc_x : bit_vector(0 to 15) := "0001001000110100";
    constant v_desc_b : bit_vector(15 downto 0) := X"dead";
    constant v_desc_x : bit_vector(15 downto 0) := "1101111010101101";
    constant v_asc_short : bit_vector(0 to 12) := "0001001000110";
    constant v_desc_short : bit_vector(12 downto 0) := "1101111010101";
  begin
    -- LRM: Hex strings are equal to 4-bit string expanded in lexical
    -- order.
    assert_equal("Literals", v_asc_b, v_asc_x, failure);
    assert_equal("Literals", v_desc_b, v_desc_x, failure);
    assert_equal("to_string", to_string(v_asc_b), "0001001000110100", failure);
    assert_equal("to_hex_string", to_hex_string(v_asc_b), "1234", failure);
    assert_equal("to_string", to_string(v_desc_b), "1101111010101101", failure);
    assert_equal("to_hex_string", to_hex_string(v_desc_b), "dead", failure);
    assert_equal("to_string", to_string(v_asc_short), "0001001000110", failure);
    assert_equal("to_string", to_string(v_desc_short), "1101111010101", failure);
    assert_equal("to_hex_string", to_hex_string(v_asc_short), "0246", failure);
    assert_equal("to_hex_string", to_hex_string(v_desc_short), "1bd5", failure);
    assert_equal("str_param_extract",
                 str_param_extract("something(something_params) other(other_params)",
                                   "something"), "something_params",
                 failure);
    assert_equal("strstr 4", strstr("something", "thing"), 4, failure);
    assert_equal("strstr -1", strstr("something", "lol"), -1, failure);
    assert_equal("strchr 4", strchr("abcdef", 'e'), 4, failure);
    assert_equal("strchr -1", strchr("abcdef", 'g'), -1, failure);
    assert_equal("str *", "abcdef" * 3, string'("abcdefabcdefabcdef"), failure);
    assert_equal("str_param_extract",
                 str_param_extract("something(something_params) other(other_params)",
                                   "lol"), "",
                 failure);
    assert_equal("str_param_extract",
                 str_param_extract("something(something_params(nested)) other(other_params)",
                                   "something_params"), "",
                 failure);

    assert false report "Test0 Done" severity note;
    wait;
  end process;

end;
