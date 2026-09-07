library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_logic, nsl_indication, nsl_memory;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_indication.font.all;

entity terminal_text_buffer_colormap is
  generic(
    row_count_l2_c: positive;
    column_count_l2_c: positive;

    character_count_l2_c : positive;

    color_count_l2_c : natural;
    font_c: nsl_data.bytestream.byte_string;

    underline_support_c: boolean := false;

    font_hscale_c: positive := 1;
    font_vscale_c: positive := 1
    );
  port(
    video_clock_i : in  std_ulogic;
    video_reset_n_i : in std_ulogic;

    sof_i : in  std_ulogic;
    sol_i : in  std_ulogic;
    color_ready_i : in std_ulogic;
    color_valid_o : out std_ulogic;
    color_o : out unsigned(color_count_l2_c-1 downto 0);

    term_clock_i : in  std_ulogic;
    term_reset_n_i : in std_ulogic;
    
    row_i : in unsigned(row_count_l2_c-1 downto 0);
    column_i : in unsigned(column_count_l2_c-1 downto 0);

    enable_i : in std_ulogic;
    write_i : in std_ulogic;
    character_i : in unsigned(character_count_l2_c-1 downto 0);
    underline_i : in std_ulogic := '0';
    foreground_i : in unsigned(color_count_l2_c-1 downto 0);
    background_i : in unsigned(color_count_l2_c-1 downto 0);

    character_o : out unsigned(character_count_l2_c-1 downto 0);
    underline_o : out std_ulogic;
    foreground_o : out unsigned(color_count_l2_c-1 downto 0);
    background_o : out unsigned(color_count_l2_c-1 downto 0)
    );
end entity;

architecture beh of terminal_text_buffer_colormap is

  subtype row_t is unsigned(row_count_l2_c-1 downto 0);
  subtype column_t is unsigned(column_count_l2_c-1 downto 0);
  subtype character_t is unsigned(character_count_l2_c-1 downto 0);
  subtype color_index_t is unsigned(color_count_l2_c-1 downto 0);

  -- Cell memory is the character+coloring+underline memory
  -- We have as many as characters on the screen
  subtype cell_address_t is unsigned(row_count_l2_c+column_count_l2_c-1 downto 0);

  type cell_t is
  record
    char: character_t;
    fg, bg: color_index_t;
    underline: std_ulogic;
  end record;

  constant cell_packed_length_c: natural :=
    character_t'length
    + if_else(underline_support_c, 1, 0)
    + color_index_t'length
    + color_index_t'length;
  subtype cell_packed_t is std_ulogic_vector(cell_packed_length_c-1 downto 0);

  function cell_pack(cell: cell_t) return cell_packed_t
  is
  begin
    return if_else(underline_support_c,
                   std_ulogic_vector'(0 => cell.underline),
                   std_ulogic_vector'(""))
      & std_ulogic_vector(cell.char)
      & std_ulogic_vector(cell.fg)
      & std_ulogic_vector(cell.bg);
  end function;

  function cell_unpack(enc: cell_packed_t) return cell_t
  is
    variable ret: cell_t;
  begin
    ret.char := unsigned(enc(color_index_t'length*2+character_t'length-1
                             downto color_index_t'length*2));
    ret.fg := unsigned(enc(color_index_t'length*2-1
                           downto color_index_t'length));
    ret.bg := unsigned(enc(color_index_t'length-1 downto 0));
    ret.underline := to_logic(underline_support_c) and enc(enc'left);
    return ret;
  end function;

  signal user_cell_addr_s, video_cell_addr_s: cell_address_t;
  signal user_cell_wdata_s, user_cell_rdata_s, video_cell_rdata_s: cell_packed_t;
  signal user_rcell_s, video_cell_s: cell_t;
  signal video_cell_en_s: std_ulogic;
  signal video_row_s: row_t;
  signal video_column_s: column_t;

begin

  user_cell_addr_s <= row_i & column_i;
  user_cell_wdata_s <= cell_pack(cell_t'(
    char => character_i,
    fg => foreground_i,
    bg => background_i,
    underline => underline_i
    ));
  user_rcell_s <= cell_unpack(user_cell_rdata_s);
  character_o <= user_rcell_s.char;
  underline_o <= user_rcell_s.underline;
  foreground_o <= user_rcell_s.fg;
  background_o <= user_rcell_s.bg;

  memory: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => cell_address_t'length,
      word_size_c => cell_packed_t'length,
      data_word_count_c => 1,
      registered_output_c => false,
      b_can_write_c => false
      )
    port map(
      a_clock_i => term_clock_i,
      a_enable_i => enable_i,
      a_write_en_i(0) => write_i,
      a_address_i => user_cell_addr_s,
      a_data_i => user_cell_wdata_s,
      a_data_o => user_cell_rdata_s,

      b_clock_i => video_clock_i,
      b_enable_i => video_cell_en_s,
      b_address_i => video_cell_addr_s,
      b_data_o => video_cell_rdata_s
      );

  video_cell_addr_s <= video_row_s & video_column_s;
  video_cell_s <= cell_unpack(video_cell_rdata_s);

  generator: work.terminal.terminal_frame_generator
    generic map(
      row_count_l2_c => row_count_l2_c,
      column_count_l2_c => column_count_l2_c,
      character_count_l2_c => character_count_l2_c,
      color_count_l2_c => color_count_l2_c,
      font_c => font_c,
      underline_support_c => underline_support_c,
      font_hscale_c => font_hscale_c,
      font_vscale_c => font_vscale_c,
      cell_latency_c => 1
      )
    port map(
      clock_i => video_clock_i,
      reset_n_i => video_reset_n_i,

      sof_i => sof_i,
      sol_i => sol_i,
      color_ready_i => color_ready_i,
      color_valid_o => color_valid_o,
      color_o => color_o,

      cell_enable_o => video_cell_en_s,
      cell_row_o => video_row_s,
      cell_column_o => video_column_s,
      cell_character_i => video_cell_s.char,
      cell_underline_i => video_cell_s.underline,
      cell_foreground_i => video_cell_s.fg,
      cell_background_i => video_cell_s.bg
      );

end architecture;
