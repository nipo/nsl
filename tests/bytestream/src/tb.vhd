library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;

entity tb is
end tb;

architecture arch of tb is
begin

  literal_test: process
    constant data_suv : byte_string := from_suv(x"12345678");
    constant data_hex : byte_string := from_hex("12345678");
  begin

    assert_equal("literals", data_suv, data_hex, failure);
    
    assert false report "Literal test done" severity note;
    wait;
  end process;

  endian_test: process
    constant data : byte_string := from_hex("12345678");
  begin

    assert_equal("le32_read", from_le(data), x"78563412", failure);
    assert_equal("be32_read", from_be(data), x"12345678", failure);
    assert_equal("le32_write", to_le(x"78563412"), data, failure);
    assert_equal("be32_write", to_be(x"12345678"), data, failure);
    
    assert false report "Endian test done" severity note;
    wait;
  end process;

end;
