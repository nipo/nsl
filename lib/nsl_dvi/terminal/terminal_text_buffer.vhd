library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_math, nsl_logic, nsl_indication, nsl_memory;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_indication.font.all;

entity terminal_text_buffer is
  generic(
    row_count_l2_c: positive;
    column_count_l2_c: positive;

    character_count_l2_c : positive;

    color_palette_c : nsl_color.rgb.rgb24_vector;

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
    pixel_ready_i : in std_ulogic;
    pixel_valid_o : out std_ulogic;
    pixel_o : out nsl_color.rgb.rgb24;

    term_clock_i : in  std_ulogic;
    term_reset_n_i : in std_ulogic;
    
    row_i : in unsigned(row_count_l2_c-1 downto 0);
    column_i : in unsigned(column_count_l2_c-1 downto 0);

    enable_i : in std_ulogic;
    write_i : in std_ulogic;
    character_i : in unsigned(character_count_l2_c-1 downto 0);
    underline_i : in std_ulogic := '0';
    foreground_i : in unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
    background_i : in unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);

    character_o : out unsigned(character_count_l2_c-1 downto 0);
    underline_o : out std_ulogic;
    foreground_o : out unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
    background_o : out unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0)
    );
end entity;

architecture beh of terminal_text_buffer is

  constant color_count_l2_c : natural := nsl_math.arith.log2(color_palette_c'length);
  signal color_ready_s, color_valid_s : std_ulogic;
  signal color_s : unsigned(color_count_l2_c-1 downto 0);

begin
  
  term: work.terminal.terminal_text_buffer_colormap
    generic map(
      row_count_l2_c => row_count_l2_c,
      column_count_l2_c => column_count_l2_c,
      character_count_l2_c => character_count_l2_c,
      color_count_l2_c => color_count_l2_c,
      font_c => font_c,
      underline_support_c => underline_support_c,
      font_hscale_c => font_hscale_c,
      font_vscale_c => font_vscale_c
      )
    port map(
      video_clock_i => video_clock_i,
      video_reset_n_i => video_reset_n_i,
      sof_i => sof_i,
      sol_i => sol_i,
      color_ready_i => color_ready_s,
      color_valid_o => color_valid_s,
      color_o => color_s,

      term_clock_i => term_clock_i,
      term_reset_n_i => term_reset_n_i,
      
      row_i => row_i,
      column_i => column_i,

      enable_i => enable_i,
      write_i => write_i,
      character_i => character_i,
      underline_i => underline_i,
      foreground_i => foreground_i,
      background_i => background_i,

      character_o => character_o,
      underline_o => underline_o,
      foreground_o => foreground_o,
      background_o => background_o
      );

  colormap: work.colormap.dvi_colormap_lookup
    generic map(
      color_count_l2_c => color_count_l2_c
      )
    port map(
      clock_i => video_clock_i,
      reset_n_i => video_reset_n_i,
      palette_i => color_palette_c,
      sof_i => sof_i,
      sol_i => sol_i,
      pixel_ready_i => pixel_ready_i,
      pixel_valid_o => pixel_valid_o,
      pixel_o => pixel_o,
      color_ready_o => color_ready_s,
      color_valid_i => color_valid_s,
      color_i => color_s
      );
  
end architecture;
