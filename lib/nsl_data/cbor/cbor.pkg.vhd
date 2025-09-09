library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_data, nsl_math;
use nsl_math.arith.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- Concise Binary Object Representation (CBOR)
package cbor is

  -- Flattened type for a CBOR item
  type kind_t is (
    KIND_INVALID,
    KIND_POSITIVE,
    KIND_NEGATIVE,
    KIND_BSTR,
    KIND_TSTR,
    KIND_ARRAY,
    KIND_MAP,
    KIND_TAG,
    KIND_SIMPLE,
    KIND_BREAK,
    KIND_FLOAT16,
    KIND_FLOAT32,
    KIND_FLOAT64,
    KIND_TRUE,
    KIND_FALSE,
    KIND_NULL,
    KIND_UNDEFINED
    );

  -- A parser context, able to parse items fed byte by byte. See
  -- reset, feed, is_last, is_done, kind, arg, arg_int below.
  type parser_t is
  record
    header_valid: boolean;
    kind: kind_t;
    arg_left: integer range 0 to 8;
    arg: byte_string(0 to 7);
    undefinite : boolean;
  end record;

  -- Resets a parser for next item parsing
  function reset return parser_t;
  -- Feeds a byte in a parser, returns the next state
  function feed(parser: parser_t;
                data: byte) return parser_t;
  -- Tells whether the state, after processing passed byte, will be
  -- final or not
  function is_last(parser: parser_t;
                   data: byte) return boolean;
  -- Tells whether the state is final.
  function is_done(parser: parser_t) return boolean;
  -- Retrieves the kind of the item that has been parsed.
  function kind(parser: parser_t) return kind_t;
  -- Retrieves the argument as an unsigned value of width w.
  function arg(parser: parser_t; w: positive) return unsigned;
  -- Retrieves the argument as an integer.
  function arg_int(parser: parser_t) return integer;

  -- Serializes a full item of type positive. Will encode the value
  -- with the minimum count of bytes.
  function cbor_positive(value: natural) return byte_string;
  -- Serializes a full item of type negative. Will encode the value
  -- with the minimum count of bytes. Passed value is the actual value
  -- (negative).
  function cbor_negative(value: integer) return byte_string;
  -- Serializes a number, depending on sign of the value parameter, it
  -- spills a positive or negative item
  function cbor_number(value: integer) return byte_string;
  -- Serializes a definite byte string (including data)
  function cbor_bstr(value: byte_string) return byte_string;
  -- Serializes a definite text string (including data)
  function cbor_tstr(value: string) return byte_string;
  -- Serializes an array header (if length is passed), or undefinite
  -- (if negative or default). Contents are not handled here.
  function cbor_array_hdr(length: integer := -1) return byte_string;
  -- Serializes a map header (if length is passed), or undefinite
  -- (if negative or default). Contents are not handled here.
  function cbor_map_hdr(length: integer := -1) return byte_string;
  -- Serializes a tag item. Contained item may be concatinated after.
  function cbor_tag_hdr(value: natural) return byte_string;
  -- Serializes a simple item.
  function cbor_simple(value: natural) return byte_string;
  -- Serializes true (simple(21))
  function cbor_true return byte_string;
  -- Serializes false (simple(20))
  function cbor_false return byte_string;
  -- Serializes null (simple(22))
  function cbor_null return byte_string;
  -- Serializes undefined (simple(23))
  function cbor_undefined return byte_string;
  -- Serializes break (7.31)
  function cbor_break return byte_string;
  -- Serializes an array. This function supports up to 32
  -- elements. First empty argument tells the end of the array. Count
  -- is implied.  Must be passed encoded items.
  function cbor_array(
    i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13, i14, i15,
    i16, i17, i18, i19, i20, i21, i22, i23, i24, i25, i26, i27, i28, i29, i30, i31
    : byte_string := null_byte_string
    ) return byte_string;
  -- Serializes a map. This function supports up to 32 pairs. First
  -- empty argument as key tells the end of the map. Count is implied.
  -- Must be passed encoded items both for key and values.
  function cbor_map(
    k0, v0, k1, v1, k2, v2, k3, v3, k4, v4, k5, v5, k6, v6, k7, v7,
    k8, v8, k9, v9, k10, v10, k11, v11, k12, v12, k13, v13, k14, v14, k15, v15,
    k16, v16, k17, v17, k18, v18, k19, v19, k20, v20, k21, v21, k22, v22, k23, v23,
    k24, v24, k25, v25, k26, v26, k27, v27, k28, v28, k29, v29, k30, v30, k31, v31
    : byte_string := null_byte_string
    ) return byte_string;
  -- Serializes a tag and a contained item. Item must be passed
  -- encoded.
  function cbor_tagged(tag: natural; item: byte_string) return byte_string;

  -- Serializes an undefinite byte string. Must be passed a
  -- concatination of encoded definite byte strings
  function cbor_bstr_undef(elements: byte_string) return byte_string;
  -- Serializes an undefinite text string. Must be passed a
  -- concatination of encoded definite text strings
  function cbor_tstr_undef(elements: byte_string) return byte_string;
  -- Serializes an undefinite array. Must be passed a
  -- concatination of encoded items
  function cbor_array_undef(elements: byte_string) return byte_string;
  -- Serializes an undefinite map. Must be passed a
  -- concatination of encoded pairs of items
  function cbor_map_undef(elements: byte_string) return byte_string;

  -- Spills the diagnostic data for passed encoded CBOR payload.
  function cbor_diag(data: byte_string) return string;
  
end package;

package body cbor is

  function reset return parser_t
  is
    variable ret: parser_t;
  begin
    ret.header_valid := false;
    ret.arg := (others => dontcare_byte_c);
    ret.arg_left := 0;
    ret.kind := KIND_INVALID;
    ret.undefinite := false;
    return ret;
  end function;

  function feed(parser: parser_t;
                data: byte) return parser_t
  is
    variable ret: parser_t;
    constant major: integer range 0 to 7 := to_integer(unsigned(data(7 downto 5)));
    constant argument: integer range 0 to 31 := to_integer(unsigned(data(4 downto 0)));
  begin
    if parser.header_valid then
      ret := parser;
      assert parser.arg_left /= 0
        report "Arg parsing overflow"
        severity failure;
      ret.arg := shift_left(parser.arg, data);
      ret.arg_left := parser.arg_left - 1;
    else
      ret.header_valid := true;
      ret.undefinite := false;
      ret.arg_left := 0;
      ret.arg := (others => x"00");
      ret.kind := KIND_INVALID;

      case major is
        when 0 =>
          ret.kind := KIND_POSITIVE;
        when 1 =>
          ret.kind := KIND_NEGATIVE;
        when 2 =>
          ret.kind := KIND_BSTR;
        when 3 =>
          ret.kind := KIND_TSTR;
        when 4 =>
          ret.kind := KIND_ARRAY;
        when 5 =>
          ret.kind := KIND_MAP;
        when 6 =>
          ret.kind := KIND_TAG;
        when 7 =>
          case argument is
            when 24 =>
              ret.kind := KIND_SIMPLE;
            when 25 =>
              ret.kind := KIND_FLOAT16;
            when 26 =>
              ret.kind := KIND_FLOAT32;
            when 27 =>
              ret.kind := KIND_FLOAT64;
            when 20 =>
              ret.kind := KIND_FALSE;
            when 21 =>
              ret.kind := KIND_TRUE;
            when 22 =>
              ret.kind := KIND_NULL;
            when 23 =>
              ret.kind := KIND_UNDEFINED;
            when 31 =>
              ret.kind := KIND_BREAK;
            when others =>
              ret.kind := KIND_SIMPLE;
          end case;
      end case;

      if argument = 24 then
        ret.arg_left := 1;
      elsif argument = 25 then
        ret.arg_left := 2;
      elsif argument = 26 then
        ret.arg_left := 4;
      elsif argument = 27 then
        ret.arg_left := 8;
      elsif argument = 31 then
        ret.undefinite := true;
      else
        ret.arg := (0 to 6 => x"00",
                    7 => "000" & data(4 downto 0));
      end if;
    end if;

    return ret;
  end function;

  function is_last(parser: parser_t;
                   data: byte) return boolean
  is
    constant argument: integer range 0 to 31 := to_integer(unsigned(data(4 downto 0)));
  begin
    if parser.header_valid then
      return parser.arg_left = 1;
    else
      return argument < 24 or argument >= 28;
    end if;
  end function;

  function is_done(parser: parser_t) return boolean
  is
  begin
    return parser.header_valid and parser.arg_left = 0;
  end function;

  function kind(parser: parser_t) return kind_t
  is
  begin
    return parser.kind;
  end function;

  function arg(parser: parser_t; w: positive) return unsigned
  is
    variable ret: unsigned(63 downto 0) := from_be(parser.arg);
  begin
    return ret(w-1 downto 0);
  end function;

  function arg_int(parser: parser_t) return integer
  is
  begin
    return to_integer(arg(parser, 32));
  end function;

  function item_encode_undef(major: integer range 0 to 7)
    return byte_string
  is
    constant maj_suv : std_ulogic_vector := std_ulogic_vector(to_unsigned(major, 3));
  begin
    return (0 => maj_suv & "11111");
  end function;

  -- Remove 0-padding of an unsigned
  function unpad(v: unsigned) return unsigned
  is
    alias xv: unsigned(v'length-1 downto 0) is v;
  begin
    for i in xv'left downto 0
    loop
      if xv(i) /= '0' then
        return xv(i downto 0);
      end if;
    end loop;

    return "";
  end function;

  function item_encode(major: integer range 0 to 7;
                       argument: unsigned)
    return byte_string
  is
    constant sarg : unsigned := unpad(argument);
    constant xarg : unsigned(sarg'length-1 downto 0) := sarg;
    constant maj_suv : std_ulogic_vector := std_ulogic_vector(to_unsigned(major, 3));
  begin
    if xarg'length <= 8 then
      if xarg'length = 0 or xarg < 24 then
        return (0 => maj_suv & std_ulogic_vector(resize(xarg, 5)));
      else
        return from_suv(maj_suv & "11000") & to_be(resize(xarg, 8));
      end if;
    elsif xarg'length <= 16 then
      return from_suv(maj_suv & "11001") & to_be(resize(xarg, 16));
    elsif xarg'length <= 32 then
      return from_suv(maj_suv & "11010") & to_be(resize(xarg, 32));
    elsif xarg'length <= 64 then
      return from_suv(maj_suv & "11011") & to_be(resize(xarg, 64));
    else
      assert false
        report "Argument too big"
        severity failure;
    end if;
  end function;

  function cbor_positive(value: natural) return byte_string
  is
  begin
    return item_encode(0, to_unsigned_auto(value));
  end function;

  function cbor_negative(value: integer) return byte_string
  is
  begin
    return item_encode(1, to_unsigned_auto(-value-1));
  end function;

  function cbor_number(value: integer) return byte_string
  is
  begin
    if value < 0 then
      return cbor_negative(value);
    else
      return cbor_positive(value);
    end if;
  end function;

  function cbor_bstr(value: byte_string) return byte_string
  is
  begin
    return item_encode(2, to_unsigned_auto(value'length)) & value;
  end function;

  function cbor_tstr(value: string) return byte_string
  is
    constant bs: byte_string := to_byte_string(value);
  begin
    return item_encode(3, to_unsigned_auto(bs'length)) & bs;
  end function;

  function cbor_array_hdr(length: integer := -1) return byte_string
  is
  begin
    if length < 0 then
      return item_encode_undef(4);
    else
      return item_encode(4, to_unsigned_auto(length));
    end if;
  end function;

  function cbor_map_hdr(length: integer := -1) return byte_string
  is
  begin
    if length < 0 then
      return item_encode_undef(5);
    else
      return item_encode(5, to_unsigned_auto(length));
    end if;
  end function;

  function cbor_tag_hdr(value: natural) return byte_string
  is
  begin
    return item_encode(6, to_unsigned_auto(value));
  end function;

  function cbor_false return byte_string
  is
  begin
    return item_encode(7, "10100");
  end function;

  function cbor_true return byte_string
  is
  begin
    return item_encode(7, "10101");
  end function;

  function cbor_null return byte_string
  is
  begin
    return item_encode(7, "10110");
  end function;

  function cbor_undefined return byte_string
  is
  begin
    return item_encode(7, "10111");
  end function;

  function cbor_break return byte_string
  is
  begin
    return item_encode_undef(7);
  end function;

  function cbor_simple(value: natural) return byte_string
  is
  begin
    return item_encode(7, to_unsigned_auto(value));
  end function;

  procedure cbor_diag_convert(
    variable output: inout line;
    variable input: inout byte_stream)
  is
    variable p: parser_t := reset;
    variable d: byte;
    variable blob: byte_stream;
    variable data: byte_string(1 to 8);
  begin
    while not is_done(p)
    loop
      read(input, d);
      p := feed(p, d);
    end loop;

    case p.kind is
      when KIND_INVALID =>
        write(output, string'("<invalid>"));

      when KIND_POSITIVE =>
        write(output, to_string(arg_int(p)));

      when KIND_NEGATIVE =>
        write(output, to_string(-1-arg_int(p)));

      when KIND_BSTR =>
        if p.undefinite then
          write(output, string'("(_ "));
          while input.all'length /= 0 and input.all(input.all'left) /= x"ff"
          loop
            cbor_diag_convert(output, input);
            if input.all(input.all'left) /= x"ff" then
              write(output, string'(", "));
            end if;
          end loop;
          write(output, string'(")"));
        else
          blob := new byte_string(1 to arg_int(p));
          read(input, blob.all);
          write(output, "h'"&to_hex_string(blob.all)&"'");
          deallocate(blob);
        end if;

      when KIND_TSTR =>
        if p.undefinite then
          write(output, string'("(_ "));
          while input.all(input.all'left) /= x"ff"
          loop
            cbor_diag_convert(output, input);
            if input.all(input.all'left) /= x"ff" then
              write(output, string'(", "));
            end if;
          end loop;
          write(output, string'(")"));
        else
          blob := new byte_string(1 to arg_int(p));
          read(input, blob.all);
          write(output, '"'&to_character_string(blob.all)&'"');
          deallocate(blob);
        end if;

      when KIND_ARRAY =>
        if p.undefinite then
          write(output, string'("[_ "));
          while input.all(input.all'left) /= x"ff"
          loop
            cbor_diag_convert(output, input);
            if input.all(input.all'left) /= x"ff" then
              write(output, string'(", "));
            end if;
          end loop;
          write(output, string'("]"));
        else
          write(output, string'("["));
          for i in 1 to arg_int(p)
          loop
            cbor_diag_convert(output, input);
            if i /= arg_int(p) then
              write(output, string'(", "));
            end if;
          end loop;
          write(output, string'("]"));
        end if;

      when KIND_MAP =>
        if p.undefinite then
          write(output, string'("{_ "));
          undefinite: while input.all(input.all'left) /= x"ff"
          loop
            cbor_diag_convert(output, input);
            if input.all(input.all'left) = x"ff" then
              exit undefinite;
            end if;
            write(output, string'(": "));
            cbor_diag_convert(output, input);
            if input.all(input.all'left) /= x"ff" then
              write(output, string'(", "));
            end if;
          end loop;
          write(output, string'("}"));
        else
          write(output, string'("{"));
          for i in 1 to arg_int(p)
          loop
            cbor_diag_convert(output, input);
            write(output, string'(": "));
            cbor_diag_convert(output, input);
            if i /= arg_int(p) then
              write(output, string'(", "));
            end if;
          end loop;
          write(output, string'("}"));
        end if;

      when KIND_TAG =>
        write(output, to_string(arg_int(p))&"(");
        cbor_diag_convert(output, input);
        write(output, string'(")"));

      when KIND_SIMPLE =>
        write(output, "simple("&to_string(arg_int(p))&")");

      when KIND_BREAK =>
        write(output, string'("break"));

      when KIND_FLOAT16 =>
        read(input, data(1 to 2));
        write(output, "f16("&to_hex_string(data(1 to 2))&")");

      when KIND_FLOAT32 =>
        read(input, data(1 to 4));
        write(output, "f32("&to_hex_string(data(1 to 4))&")");

      when KIND_FLOAT64 =>
        read(input, data(1 to 8));
        write(output, "f16("&to_hex_string(data(1 to 8))&")");

      when KIND_TRUE =>
        write(output, string'("true"));

      when KIND_FALSE =>
        write(output, string'("false"));

      when KIND_NULL =>
        write(output, string'("null"));

      when KIND_UNDEFINED =>
        write(output, string'("undefined"));
    end case;
  end procedure;
  
  function cbor_diag(data: byte_string) return string
  is
    variable output: line;
    variable stream: byte_stream;
  begin
    write(stream, data);

    cbor_diag_convert(output, stream);

    deallocate(stream);
    return output.all;
  end function;

  function cbor_array(
    i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13, i14, i15,
    i16, i17, i18, i19, i20, i21, i22, i23, i24, i25, i26, i27, i28, i29, i30, i31
    : byte_string := null_byte_string
    ) return byte_string
  is
  begin
    if i0'length = 0 then
      return cbor_array_hdr(length => 0);
    elsif i1'length = 0 then
      return cbor_array_hdr(length => 1) & i0;
    elsif i2'length = 0 then
      return cbor_array_hdr(length => 2) & i0 & i1;
    elsif i3'length = 0 then
      return cbor_array_hdr(length => 3) & i0 & i1 & i2;
    elsif i4'length = 0 then
      return cbor_array_hdr(length => 4) & i0 & i1 & i2 & i3;
    elsif i5'length = 0 then
      return cbor_array_hdr(length => 5) & i0 & i1 & i2 & i3 & i4;
    elsif i6'length = 0 then
      return cbor_array_hdr(length => 6) & i0 & i1 & i2 & i3 & i4 & i5;
    elsif i7'length = 0 then
      return cbor_array_hdr(length => 7) & i0 & i1 & i2 & i3 & i4 & i5 & i6;
    elsif i8'length = 0 then
      return cbor_array_hdr(length => 8) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7;
    elsif i9'length = 0 then
      return cbor_array_hdr(length => 9) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8;
    elsif i10'length = 0 then
      return cbor_array_hdr(length => 10) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9;
    elsif i11'length = 0 then
      return cbor_array_hdr(length => 11) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10;
    elsif i12'length = 0 then
      return cbor_array_hdr(length => 12) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11;
    elsif i13'length = 0 then
      return cbor_array_hdr(length => 13) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12;
    elsif i14'length = 0 then
      return cbor_array_hdr(length => 14) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13;
    elsif i15'length = 0 then
      return cbor_array_hdr(length => 15) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14;
    elsif i16'length = 0 then
      return cbor_array_hdr(length => 16) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15;
    elsif i17'length = 0 then
      return cbor_array_hdr(length => 17) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16;
    elsif i18'length = 0 then
      return cbor_array_hdr(length => 18) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17;
    elsif i19'length = 0 then
      return cbor_array_hdr(length => 19) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18;
    elsif i20'length = 0 then
      return cbor_array_hdr(length => 20) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19;
    elsif i21'length = 0 then
      return cbor_array_hdr(length => 21) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20;
    elsif i22'length = 0 then
      return cbor_array_hdr(length => 22) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21;
    elsif i23'length = 0 then
      return cbor_array_hdr(length => 23) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22;
    elsif i24'length = 0 then
      return cbor_array_hdr(length => 24) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23;
    elsif i25'length = 0 then
      return cbor_array_hdr(length => 25) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24;
    elsif i26'length = 0 then
      return cbor_array_hdr(length => 26) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25;
    elsif i27'length = 0 then
      return cbor_array_hdr(length => 27) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25 & i26;
    elsif i28'length = 0 then
      return cbor_array_hdr(length => 28) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25 & i26 & i27;
    elsif i29'length = 0 then
      return cbor_array_hdr(length => 29) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25 & i26 & i27 & i28;
    elsif i30'length = 0 then
      return cbor_array_hdr(length => 30) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25 & i26 & i27 & i28 & i29;
    elsif i31'length = 0 then
      return cbor_array_hdr(length => 31) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25 & i26 & i27 & i28 & i29 & i30;
    else
      return cbor_array_hdr(length => 32) & i0 & i1 & i2 & i3 & i4 & i5 & i6 & i7 & i8
        & i9 & i10 & i11 & i12 & i13 & i14 & i15 & i16
        & i17 & i18 & i19 & i20 & i21 & i22 & i23 & i24
        & i25 & i26 & i27 & i28 & i29 & i30 & i31;
    end if;
  end function;
    
  function cbor_map(
    k0, v0, k1, v1, k2, v2, k3, v3, k4, v4, k5, v5, k6, v6, k7, v7,
    k8, v8, k9, v9, k10, v10, k11, v11, k12, v12, k13, v13, k14, v14, k15, v15,
    k16, v16, k17, v17, k18, v18, k19, v19, k20, v20, k21, v21, k22, v22, k23, v23,
    k24, v24, k25, v25, k26, v26, k27, v27, k28, v28, k29, v29, k30, v30, k31, v31
    : byte_string := null_byte_string
    ) return byte_string
  is
  begin
    if k0'length = 0 then
      return cbor_map_hdr(length => 0);
    elsif k1'length = 0 then
      return cbor_map_hdr(length => 1) & k0 & v0;
    elsif k2'length = 0 then
      return cbor_map_hdr(length => 2) & k0 & v0 & k1 & v1;
    elsif k3'length = 0 then
      return cbor_map_hdr(length => 3) & k0 & v0 & k1 & v1 & k2 & v2;
    elsif k4'length = 0 then
      return cbor_map_hdr(length => 4) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3;
    elsif k5'length = 0 then
      return cbor_map_hdr(length => 5) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4;
    elsif k6'length = 0 then
      return cbor_map_hdr(length => 6) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5;
    elsif k7'length = 0 then
      return cbor_map_hdr(length => 7) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6;
    elsif k8'length = 0 then
      return cbor_map_hdr(length => 8) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7;
    elsif k9'length = 0 then
      return cbor_map_hdr(length => 9) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8;
    elsif k10'length = 0 then
      return cbor_map_hdr(length => 10) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9;
    elsif k11'length = 0 then
      return cbor_map_hdr(length => 11) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10;
    elsif k12'length = 0 then
      return cbor_map_hdr(length => 12) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11;
    elsif k13'length = 0 then
      return cbor_map_hdr(length => 13) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12;
    elsif k14'length = 0 then
      return cbor_map_hdr(length => 14) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13;
    elsif k15'length = 0 then
      return cbor_map_hdr(length => 15) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14;
    elsif k16'length = 0 then
      return cbor_map_hdr(length => 16) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15;
    elsif k17'length = 0 then
      return cbor_map_hdr(length => 17) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16;
    elsif k18'length = 0 then
      return cbor_map_hdr(length => 18) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17;
    elsif k19'length = 0 then
      return cbor_map_hdr(length => 19) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18;
    elsif k20'length = 0 then
      return cbor_map_hdr(length => 20) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19;
    elsif k21'length = 0 then
      return cbor_map_hdr(length => 21) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20;
    elsif k22'length = 0 then
      return cbor_map_hdr(length => 22) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21;
    elsif k23'length = 0 then
      return cbor_map_hdr(length => 23) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22;
    elsif k24'length = 0 then
      return cbor_map_hdr(length => 24) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23;
    elsif k25'length = 0 then
      return cbor_map_hdr(length => 25) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24;
    elsif k26'length = 0 then
      return cbor_map_hdr(length => 26) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25;
    elsif k27'length = 0 then
      return cbor_map_hdr(length => 27) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25 & k26 & v26;
    elsif k28'length = 0 then
      return cbor_map_hdr(length => 28) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25 & k26 & v26 & k27 & v27;
    elsif k29'length = 0 then
      return cbor_map_hdr(length => 29) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25 & k26 & v26 & k27 & v27 
        & k28 & v28;
    elsif k30'length = 0 then
      return cbor_map_hdr(length => 30) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25 & k26 & v26 & k27 & v27 
        & k28 & v28 & k29 & v29;
    elsif k31'length = 0 then
      return cbor_map_hdr(length => 31) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25 & k26 & v26 & k27 & v27 
        & k28 & v28 & k29 & v29 & k30 & v30;
    else
      return cbor_map_hdr(length => 32) & k0 & v0 & k1 & v1 & k2 & v2 & k3 & v3 
        & k4 & v4 & k5 & v5 & k6 & v6 & k7 & v7 & k8 & v8
        & k9 & v9 & k10 & v10 & k11 & v11 
        & k12 & v12 & k13 & v13 & k14 & v14 & k15 & v15 & k16 & v16
        & k17 & v17 & k18 & v18 & k19 & v19 
        & k20 & v20 & k21 & v21 & k22 & v22 & k23 & v23 & k24 & v24
        & k25 & v25 & k26 & v26 & k27 & v27 
        & k28 & v28 & k29 & v29 & k30 & v30 & k31 & v31;
    end if;
  end function;

  function cbor_tagged(tag: natural; item: byte_string) return byte_string
  is
  begin
    return cbor_tag_hdr(tag) & item;
  end function;

  function cbor_bstr_undef(elements: byte_string) return byte_string
  is
  begin
    return item_encode_undef(2) & elements & cbor_break;
  end function;

  function cbor_tstr_undef(elements: byte_string) return byte_string
  is
  begin
    return item_encode_undef(3) & elements & cbor_break;
  end function;

  function cbor_array_undef(elements: byte_string) return byte_string
  is
  begin
    return cbor_array_hdr(length => -1) & elements & cbor_break;
  end function;

  function cbor_map_undef(elements: byte_string) return byte_string
  is
  begin
    return cbor_map_hdr(length => -1) & elements & cbor_break;
  end function;

end package body;
