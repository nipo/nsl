library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_simulation.text.all;
use nsl_simulation.assertions.all;

entity tb is
end tb;

architecture arch of tb is

  constant crc_test_init : crc32 := x"ffffffff";
  constant crc_test_poly : crc32 := x"edb88320";
  constant crc_test_check : crc32 := x"00000000";
  function crc_test_update(init : crc32;
                           data : byte_string) return crc32 is
  begin
    return crc_update(init, crc_test_poly, true, true, data);
  end function;

begin

  iso14443_3: process
    constant d1234 : byte_string := from_hex("1234");
    constant d0000 : byte_string := from_hex("0000");
  begin
    
    assert_equal("ISO-14443-3 0000",
                 std_ulogic_vector(crc_iso_14443_3_a_update(crc_iso_14443_3_a_init, d0000)),
                 x"1ea0",
                 failure);

    assert_equal("ISO-14443-3 1234",
                 std_ulogic_vector(crc_iso_14443_3_a_update(crc_iso_14443_3_a_init, d1234)),
                 x"cf26",
                 failure);

    assert false report "ISO-14443-3 done" severity note;
    wait;
  end process;

  ieee_802_3: process
    constant data : byte_string := from_hex( "20cf301acea16238e0c2bd3008060001"
                                            &"0800060400016238e0c2bd300a2a2a01"
                                            &"0000000000000a2a2a02000000000000"
                                            &"00000000000000000000000022b72660");
  begin
    
    assert_equal("IEEE-802.3 compare",
                 to_le(unsigned(crc_ieee_802_3_update(crc_ieee_802_3_init, data(0 to 59)))),
                 data(60 to 63),
                 failure);

    assert_equal("IEEE-802.3 check constant",
                 std_ulogic_vector(crc_ieee_802_3_update(crc_ieee_802_3_init, data)),
                 std_ulogic_vector(crc_ieee_802_3_check),
                 failure);

    assert false report "IEEE-802.3 done" severity note;
    wait;
  end process;

  other: process
    constant data : byte_string := from_hex("313233343536373839d9c60b34");
  begin
    
    assert_equal("Other compare",
                 to_le(unsigned(crc_test_update(crc_test_init, data(0 to 8)))),
                 data(9 to 12),
                 failure);

    assert_equal("Other check constant",
                 std_ulogic_vector(crc_test_update(crc_test_init, data)),
                 std_ulogic_vector(crc_test_check),
                 failure);

    assert false report "Other done" severity note;
    wait;
  end process;
  
end;
