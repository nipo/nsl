library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.cbor.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  procedure codec_assert(ctx: string; raw: byte_string; encoded: byte_string; diag: string)
  is
    constant raw_diag : string := cbor_diag(raw);
    constant encoded_diag : string := cbor_diag(encoded);
  begin
    assert_equal(ctx & " bin repr", raw, encoded, FAILURE);
    assert_equal(ctx & " raw diag", raw_diag, diag, FAILURE);
    assert_equal(ctx & " encoded diag", encoded_diag, diag, FAILURE);

    log_info(ctx, "OK");
    wait;
  end procedure;
  
begin

  codec_assert("ne1",
               from_hex("bf6346756ef563416d7421ff"),
               cbor_map_undef(cbor_tstr("Fun") & cbor_true
                              & cbor_tstr("Amt") & cbor_number(-2)),
               "{_ ""Fun"": true, ""Amt"": -2}");

  codec_assert("narr", from_hex("820102"),
               cbor_array(cbor_number(1), cbor_number(2)),
               "[1, 2]");

  codec_assert("narr2",
               from_hex("98190102030405060708090a0b0c0d0e0f101112131415161718181819"),
               cbor_array(cbor_number(1), cbor_number(2), cbor_number(3), cbor_number(4),
                          cbor_number(5), cbor_number(6), cbor_number(7), cbor_number(8),
                          cbor_number(9), cbor_number(10), cbor_number(11), cbor_number(12),
                          cbor_number(13), cbor_number(14), cbor_number(15), cbor_number(16),
                          cbor_number(17), cbor_number(18), cbor_number(19), cbor_number(20),
                          cbor_number(21), cbor_number(22), cbor_number(23), cbor_number(24),
                          cbor_number(25)),
               "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]");

  -- From appendix A, using encoder
  codec_assert("ns43",
               from_hex("f7"),
               cbor_undefined,
               "undefined");
  codec_assert("ns44",
               from_hex("f0"),
               cbor_simple(16),
               "simple(16)");
  codec_assert("ns45",
               from_hex("f818"),
               cbor_simple(24),
               "simple(24)");
  codec_assert("ns46",
               from_hex("f8ff"),
               cbor_simple(255),
               "simple(255)");
  codec_assert("ns47",
               from_hex("c074323031332d30332d32315432303a30343a30305a"),
               cbor_tagged(0, cbor_tstr("2013-03-21T20:04:00Z")),
               "0(""2013-03-21T20:04:00Z"")");
  codec_assert("ns48",
               from_hex("c11a514b67b0"),
               cbor_tagged(1, cbor_number(1363896240)),
               "1(1363896240)");
  codec_assert("ns50",
               from_hex("d74401020304"),
               cbor_tagged(23, cbor_bstr(from_hex("01020304"))),
               "23(h'01020304')");
  codec_assert("ns51",
               from_hex("d818456449455446"),
               cbor_tagged(24, cbor_bstr(from_hex("6449455446"))),
               "24(h'6449455446')");
  codec_assert("ns52",
               from_hex("d82076687474703a2f2f7777772e6578616d706c652e636f6d"),
               cbor_tagged(32, cbor_tstr("http://www.example.com")),
               "32(""http://www.example.com"")");
  codec_assert("ns53",
               from_hex("40"),
               cbor_bstr(null_byte_string),
               "h''");
  codec_assert("ns54",
               from_hex("4401020304"),
               cbor_bstr(from_hex("01020304")),
               "h'01020304'");
  codec_assert("ns67",
               from_hex("a201020304"),
               cbor_map(cbor_number(1), cbor_number(2), cbor_number(3), cbor_number(4)),
               "{1: 2, 3: 4}");
  codec_assert("ns71",
               from_hex("5f42010243030405ff"),
               cbor_bstr_undef(cbor_bstr(from_hex("0102")) & cbor_bstr(from_hex("030405"))),
               "(_ h'0102', h'030405')");
  
end;
