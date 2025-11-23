library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;

-- Font declaration and handling utilities
--
-- Fonts are interally stored as a byte string:
-- - First byte is pixel width of one character,
-- - Second byte is pixel height of one character,
-- - Follows
--   2**character_count_l2_c
--     * align_up(width, 8) / 8
--     * height bytes of data.
--
-- Glyphs must be encoded one little-endian word per line, from
-- top to bottom, with left column at LSB, little-endian in case
-- there are more than 8 columns.  e.g.: In a 4x6 font, the 'h'
-- character would be encoded as 01 01 03 05 05 00, the 'q'
-- character as 00 00 06 05 06 04.  Bytes are used for easy
-- alignment, but only the necessary bits will actually be used
-- in the ROM:
--
-- ::
--       /----- LSB of each word
--       |  /-- MSB of each word
--       |  |
--       v  v
--      +----+----+
--      |#   |    | <- First word
--      |#   |    |
--      |##  | ## |
--      |# # |# # |
--      |# # | ## |
--      |    |  # | <- Last word
--      +----+----+
package font is

  -- Arbitrary constants for record declarations
  constant max_glyph_width_c : natural := 16;
  constant max_glyph_height_c : natural := 16;

  -- A line in a glyph after it has been parsed by declaration logic
  subtype font_define_line_t is std_ulogic_vector(0 to max_glyph_width_c-1);
  -- A vector of lines, i.e. a glyph data.
  type font_define_line_vector is array(integer range 0 to max_glyph_height_c-1) of font_define_line_t;
  -- Glyph data, as a record, only has meaning in a context where we
  -- know width and height of glyphs.
  type font_define_glyph_t is
  record
    lines: font_define_line_vector;
  end record;
  -- A vector of glyphs, i.e. a font.
  type font_define_glyph_vector is array(integer range <>) of font_define_glyph_t;

  -- An encoded font, packed for storage. This is the preferred format
  -- for generics.
  subtype font_t is byte_string;

  -- Internal
  constant na_str: string(1 to 0) := (others => '-');

  -- Font definition helper. Pass a vector of glyphs, they'll define
  -- the font.
  --
  -- Usage::
  --
  --   constant my_font_c : font_t := font_define(4, 6,
  --        glyph(" ## ",
  --              "# # ",
  --              "# # ",
  --              "# # ",
  --              "##  ",
  --              "    ") &
  --        glyph(" #  ",
  --              "##  ",
  --              " #  ",
  --              " #  ",
  --              "### ",
  --              "    ") &
  --         -- ....
  --         );
  function font_define(glyph_w, glyph_h: positive;
                       glyphs: font_define_glyph_vector) return font_t;
  -- Each glyph data, one argument per line, using space and # as
  -- drawing elements
  function glyph(a, b, c, d,
                 e, f, g, h,
                 i, j, k, l,
                 m, n, o, p: string := na_str) return font_define_glyph_t;

  -- Get glyph width
  function font_width(fnt: font_t) return natural;
  -- Get glyph height
  function font_height(fnt: font_t) return natural;
  -- Get glyph total count
  function font_glyph_count(fnt: font_t) return natural;

  -- Get glyph height index bit count
  function font_glyph_line_index_l2(fnt: font_t) return natural;
  -- Get glyph width index bit count
  function font_glyph_column_index_l2(fnt: font_t) return natural;
  -- Get glyph index bit count
  function font_glyph_index_l2(fnt: font_t) return natural;

  -- Get glyph line data for a glyph and a line in a font.
  -- Returns a vector of pixels, with left column on the left of the
  -- vector.
  function font_glyph_line_get(fnt: font_t;
                               glyph_index: natural;
                               glyph_line: natural) return std_ulogic_vector;

  -- Generate font_rom_glyph_line rom initialization constant
  function font_rom_glyph_line_data(fnt: font_t) return byte_string;

  -- A component able to give an arbitrary line of an arbitrary glyph
  -- as a rom component, with 1-cycle latency.
  component font_rom_glyph_line is
    generic(
      font_c: font_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      glyph_i: in unsigned(font_glyph_index_l2(font_c)-1 downto 0);
      line_i: in unsigned(font_glyph_line_index_l2(font_c)-1 downto 0);
      enable_i: in std_ulogic;

      -- In pixel order (left = 0 = visual left).
      line_o: out std_ulogic_vector(0 to font_width(font_c)-1)
      );
  end component;

end package;

package body font is

  function to_glyph_data(glyph_w, glyph_h: positive;
                         glyph_def: font_define_glyph_t) return byte_string
  is
    constant glyph_bytes_w_c: positive := (glyph_w + 7) / 8;
    constant glyph_bytes_c: positive := glyph_bytes_w_c * glyph_h;
    variable line_v: unsigned(glyph_w-1 downto 0);
    constant line_pad_c: unsigned(8*glyph_bytes_w_c-1 downto line_v'length)
      := (others => '0');
    variable ret: byte_string(0 to glyph_bytes_c-1);
  begin
    for l in 0 to glyph_h-1
    loop
      line_v := unsigned(bitswap(glyph_def.lines(l)(0 to glyph_w-1)));
      ret(l*glyph_bytes_w_c to (l+1)*glyph_bytes_w_c-1)
        := to_le(line_pad_c & line_v);
    end loop;
    return ret;
  end function;
  
  function font_define(glyph_w, glyph_h: positive;
                       glyphs: font_define_glyph_vector) return font_t
  is
    constant glyph_bytes_w_c: positive := (glyph_w + 7) / 8;
    constant glyph_bytes_c: positive := glyph_bytes_w_c * glyph_h;
    constant font_bytes_c: positive := glyph_bytes_c * glyphs'length;
    variable glyph_hdr_v: byte_string(0 to 1);
    variable glyph_data_v: byte_string(0 to font_bytes_c-1);
    alias xglyphs: font_define_glyph_vector(0 to glyphs'length-1) is glyphs;
  begin
    for char in xglyphs'range
    loop
      glyph_data_v(char*glyph_bytes_c to (char+1)*glyph_bytes_c-1)
        := to_glyph_data(glyph_w, glyph_h, xglyphs(char));
    end loop;

    glyph_hdr_v(0) := to_byte(glyph_w);
    glyph_hdr_v(1) := to_byte(glyph_h);
    return glyph_hdr_v & glyph_data_v;
  end function;
  
  function to_font_define_line(l: string) return font_define_line_t
  is
    alias xl: string(1 to l'length) is l;
    constant usable_count: natural := nsl_math.arith.min(font_define_line_t'length,
                                                          l'length);
    variable ret: font_define_line_t := (others => '0');
  begin
    for i in 0 to usable_count-1
    loop
      ret(i) := to_logic(xl(i+1) = '#');
    end loop;
    return ret;
  end function;

  function glyph(a, b, c, d,
                 e, f, g, h,
                 i, j, k, l,
                 m, n, o, p: string := na_str) return font_define_glyph_t
  is
    variable ret: font_define_glyph_t;
  begin
    ret.lines(0) := to_font_define_line(a);
    ret.lines(1) := to_font_define_line(b);
    ret.lines(2) := to_font_define_line(c);
    ret.lines(3) := to_font_define_line(d);
    ret.lines(4) := to_font_define_line(e);
    ret.lines(5) := to_font_define_line(f);
    ret.lines(6) := to_font_define_line(g);
    ret.lines(7) := to_font_define_line(h);
    ret.lines(8) := to_font_define_line(i);
    ret.lines(9) := to_font_define_line(j);
    ret.lines(10) := to_font_define_line(k);
    ret.lines(11) := to_font_define_line(l);
    ret.lines(12) := to_font_define_line(m);
    ret.lines(13) := to_font_define_line(n);
    ret.lines(14) := to_font_define_line(o);
    ret.lines(15) := to_font_define_line(p);
    return ret;
  end function;

  function font_width(fnt: font_t) return natural
  is
    alias xfont: byte_string(0 to fnt'length-1) is fnt;
  begin
    return to_integer(xfont(0));
  end function;

  function font_height(fnt: font_t) return natural
  is
    alias xfont: byte_string(0 to fnt'length-1) is fnt;
  begin
    return to_integer(xfont(1));
  end function;

  function font_glyph_count(fnt: font_t) return natural
  is
    constant glyph_w: positive := font_width(fnt);
    constant glyph_bytes_w_c: positive := (glyph_w + 7) / 8;
  begin
    return (fnt'length - 2) / glyph_bytes_w_c / font_height(fnt);
  end function;

  function font_glyph_index_l2(fnt: font_t) return natural
  is
  begin
    return nsl_math.arith.log2(font_glyph_count(fnt)-1);
  end function;
  
  function font_glyph_line_index_l2(fnt: font_t) return natural
  is
  begin
    return nsl_math.arith.log2(font_height(fnt)-1);
  end function;

  function font_glyph_column_index_l2(fnt: font_t) return natural
  is
  begin
    return nsl_math.arith.log2(font_width(fnt)-1);
  end function;

  function font_glyph_line_get(fnt: font_t;
                               glyph_index: natural;
                               glyph_line: natural) return std_ulogic_vector
  is
    constant glyph_w: positive := font_width(fnt);
    constant glyph_bytes_w_c: positive := (glyph_w + 7) / 8;
    constant glyph_bytes_c: positive := glyph_bytes_w_c * font_height(fnt);
    alias xfont: byte_string(0 to fnt'length-1) is fnt;
    constant glyph_line_offset_c: natural := 2+glyph_bytes_c*glyph_index;
    variable line_data_v
      : std_ulogic_vector(8*glyph_bytes_w_c-1 downto 0)
      := (others => '0');
    variable line_data_swapped_v
      : std_ulogic_vector(0 to 8*glyph_bytes_w_c-1)
      := (others => '0');
  begin
    if glyph_line_offset_c < xfont'length then
      line_data_v := std_ulogic_vector(from_le(xfont(glyph_line_offset_c to glyph_line_offset_c+glyph_bytes_w_c-1)));
    end if;
    line_data_swapped_v := bitswap(line_data_v);
    return line_data_swapped_v(0 to glyph_w-1);
  end function;

  function font_rom_glyph_line_data(fnt: font_t) return byte_string
  is
    alias xfnt: byte_string(0 to fnt'length-1) is fnt;
    constant glyph_width_c : positive := font_width(fnt);
    constant glyph_height_c : positive := font_height(fnt);
    constant glyph_index_width_c : positive := font_glyph_index_l2(fnt);
    constant glyph_line_index_width_c : positive := font_glyph_line_index_l2(fnt);

    constant line_stride_c : positive := (glyph_width_c + 7) / 8;
    constant glyph_stride_c : positive := (2**glyph_line_index_width_c) * line_stride_c;

    constant addr_width_c : positive := glyph_index_width_c + glyph_line_index_width_c;

    variable ret: byte_string(0 to line_stride_c * (2**addr_width_c) - 1)
      := (others => to_byte(0));

    constant font_data_c : byte_string(0 to fnt'length-3) := xfnt(2 to xfnt'right);
    variable glyph_data_v : byte_string(0 to line_stride_c * glyph_height_c-1);
  begin
    for glyph in 0 to font_glyph_count(fnt) - 1
    loop
      glyph_data_v := font_data_c(glyph * glyph_height_c * line_stride_c
                                  to (glyph+1) * glyph_height_c * line_stride_c - 1);
      ret(glyph * glyph_stride_c
          to glyph * glyph_stride_c + line_stride_c * glyph_height_c - 1)
        := glyph_data_v;
    end loop;
    
    return ret;
  end function;

end package body;
