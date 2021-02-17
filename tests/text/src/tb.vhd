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
    -- LRM: Hex strings are equal to 4-bit string expandedx in lexical
    -- order.
    assert v_asc_b = v_asc_x
      report "Literal failure"
      severity failure;
    assert v_desc_b = v_desc_x
      report "Literal failure"
      severity failure;

    assert to_string(v_asc_b) = "0001001000110100"
      report "to_string(""0001001000110100""/asc) failure"
      severity failure;
    assert to_hex_string(v_asc_b) = "1234"
      report "to_hex_string(x""1234""/asc) failure"
      severity failure;

    assert to_string(v_desc_b) = "1101111010101101"
      report "to_string(""1101111010101101""/desc) failure"
      severity failure;
    assert to_hex_string(v_desc_b) = "dead"
      report "to_hex_string(x""dead""/desc) failure"
      severity failure;

    assert to_string(v_asc_short) = "0001001000110"
      report "to_string(""0001001000110""/asc) failure"
      severity failure;
    assert to_string(v_desc_short) = "1101111010101"
      report "to_string(""1101111010101""/desc) failure"
      severity failure;

    assert to_hex_string(v_asc_short) = "1230"
      report "to_hex_string(""0001001000110""/asc) != ""1234"" (= " & to_hex_string(v_asc_short) & ")"
      severity failure;

    assert to_hex_string(v_desc_short) = "dea8"
      report "to_hex_string(""1101111010101""/asc) != ""dea8"" (= " & to_hex_string(v_desc_short) & ")"
      severity failure;

    assert false report "Test0 Done" severity note;
    wait;
  end process;

end;
