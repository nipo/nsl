library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_memory, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.font.all;

entity font_rom_glyph_line is
  generic(
    font_c: font_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    glyph_i: in unsigned(font_glyph_index_l2(font_c)-1 downto 0);
    line_i: in unsigned(font_glyph_line_index_l2(font_c)-1 downto 0);
    enable_i: in std_ulogic;

    line_o: out std_ulogic_vector(0 to font_width(font_c)-1)
    );
end entity;

architecture beh of font_rom_glyph_line is
  
  constant glyph_width_c : positive := font_width(font_c);
  constant glyph_line_bytes_c : positive := (font_width(font_c) + 7) / 8;
  constant addr_width_c : positive := glyph_i'length + line_i'length;
  constant font_data_c : byte_string := font_rom_glyph_line_data(font_c);
  
  signal addr_s: unsigned(addr_width_c-1 downto 0);
  signal data_s: std_ulogic_vector(glyph_line_bytes_c*8-1 downto 0);
  
begin
  
  rom: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => addr_width_c,
      word_byte_count_c => glyph_line_bytes_c,
      contents_c => font_data_c,
      little_endian_c => true
      )
    port map(
      clock_i => clock_i,
      read_i => enable_i,
      address_i => addr_s,
      data_o => data_s
      );

  addr_s <= glyph_i & line_i;
  line_o <= bitswap(data_s(glyph_width_c-1 downto 0));
  
end architecture;
