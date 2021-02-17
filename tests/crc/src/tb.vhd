library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

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
    constant context: log_context := "ISO-14443-3";
  begin
    assert_equal(context, "0000",
                 std_ulogic_vector(crc_iso_14443_3_a_update(crc_iso_14443_3_a_init, from_hex("0000"))),
                 x"1ea0",
                 failure);

    assert_equal(context, "1234",
                 std_ulogic_vector(crc_iso_14443_3_a_update(crc_iso_14443_3_a_init, from_hex("1234"))),
                 x"cf26",
                 failure);

    log_info(context, "done");
    wait;
  end process;

  ieee_802_3: process
    constant context: log_context := "IEEE-802.3";
    constant data : byte_string := from_hex( "20cf301acea16238e0c2bd3008060001"
                                            &"0800060400016238e0c2bd300a2a2a01"
                                            &"0000000000000a2a2a02000000000000"
                                            &"00000000000000000000000022b72660");
  begin
    
    assert_equal(context, "compare",
                 to_le(unsigned(crc_ieee_802_3_update(crc_ieee_802_3_init, data(0 to 59)))),
                 data(60 to 63),
                 failure);

    assert_equal(context, "check constant",
                 std_ulogic_vector(crc_ieee_802_3_update(crc_ieee_802_3_init, data)),
                 std_ulogic_vector(crc_ieee_802_3_check),
                 failure);

    log_info(context, "done");
    wait;
  end process;

  other: process
    constant context: log_context := "Other";
    constant data : byte_string := from_hex("313233343536373839d9c60b34");
  begin
    
    assert_equal(context, "checking CRC to appended",
                 to_le(unsigned(crc_test_update(crc_test_init, data(0 to 8)))),
                 data(9 to 12),
                 failure);

    assert_equal(context, "checking whole message CRC to constant",
                 std_ulogic_vector(crc_test_update(crc_test_init, data)),
                 std_ulogic_vector(crc_test_check),
                 failure);

    log_info(context, "done");
    wait;
  end process;
  
end;
