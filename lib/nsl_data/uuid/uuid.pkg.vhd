library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_data, nsl_math;
use nsl_math.arith.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

package uuid is

  subtype uuid_t is byte_string(0 to 15);

--  type rfc4122_version_t is (
--    RFC4122_VER0,
--    RFC4122_TIME,
--    RFC4122_DCE,
--    RFC4122_NAME_MD5,
--    RFC4122_RANDOM,
--    RFC4122_NAME_SHA1,
--    RFC4122_VER6,
--    RFC4122_VER7,
--    RFC4122_VER8,
--    RFC4122_VER9,
--    RFC4122_VER10,
--    RFC4122_VER11,
--    RFC4122_VER12,
--    RFC4122_VER13,
--    RFC4122_VER14,
--    RFC4122_VER15
--    );
--
--  type rfc4122_uuid_t is
--  record
--    version: rfc4122_version_t;
--    timestamp: unsigned(59 downto 0);
--    clock_seq: unsigned(13 downto 0);
--    node: unsigned(47 downto 0);
--  end record;
  
  function uuid(str: string) return uuid_t;
  function to_string(uuid: uuid_t) return string;

--  function is_rfc4122(uuid: uuid_t) return boolean;
--  function rfc4122_parse(uuid: uuid_t) return rfc4122_uuid_t;
  
end package;

package body uuid is

  function uuid(str: string) return uuid_t
  is
    alias xu: string(1 to 36) is str;
    variable ret: uuid_t;
  begin
    assert xu(9) = '-'
      report "Bad UUID format"
      severity failure;
    assert xu(14) = '-'
      report "Bad UUID format"
      severity failure;
    assert xu(19) = '-'
      report "Bad UUID format"
      severity failure;
    assert xu(24) = '-'
      report "Bad UUID format"
      severity failure;

    ret(0 to 3) := from_hex(xu(1 to 8));
    ret(4 to 5) := from_hex(xu(10 to 13));
    ret(6 to 7) := from_hex(xu(15 to 18));
    ret(8 to 9) := from_hex(xu(20 to 23));
    ret(10 to 15) := from_hex(xu(25 to 36));

    return ret;
  end function;

  function to_string(uuid: uuid_t) return string
  is
  begin
    return to_hex_string(uuid(0 to 3))
      & "-" & to_hex_string(uuid(4 to 5))
      & "-" & to_hex_string(uuid(6 to 7))
      & "-" & to_hex_string(uuid(8 to 9))
      & "-" & to_hex_string(uuid(10 to 15));
  end function;

--  function is_rfc4122(uuid: uuid_t) return boolean;
--  function rfc4122_parse(uuid: uuid_t) return rfc4122_uuid_t;

end package body;
