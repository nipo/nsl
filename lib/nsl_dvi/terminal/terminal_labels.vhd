library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_math, nsl_indication, work;
use work.terminal.all;

entity terminal_labels is
  generic(
    row_count_l2_c: positive;
    column_count_l2_c: positive;
    character_count_l2_c : positive;
    color_palette_c : nsl_color.rgb.rgb24_vector;
    font_c: nsl_indication.font.font_t;
    labels_c: label_vector;
    blank_character_c: natural := 32;
    blank_color_c: natural := 0;
    underline_support_c: boolean := false;
    font_hscale_c: positive := 1;
    font_vscale_c: positive := 1
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    sof_i : in  std_ulogic;
    sol_i : in  std_ulogic;
    pixel_ready_i : in std_ulogic;
    pixel_valid_o : out std_ulogic;
    pixel_o : out nsl_color.rgb.rgb24;

    text_i : in string;
    color_i : in label_color_vector
    );
end entity;

architecture beh of terminal_labels is

  constant color_count_l2_c : natural := nsl_math.arith.log2(color_palette_c'length);
  signal color_ready_s, color_valid_s : std_ulogic;
  signal color_s : unsigned(color_count_l2_c-1 downto 0);

begin

  labels: work.terminal.terminal_labels_colormap
    generic map(
      row_count_l2_c => row_count_l2_c,
      column_count_l2_c => column_count_l2_c,
      character_count_l2_c => character_count_l2_c,
      color_count_l2_c => color_count_l2_c,
      font_c => font_c,
      labels_c => labels_c,
      blank_character_c => blank_character_c,
      blank_color_c => blank_color_c,
      underline_support_c => underline_support_c,
      font_hscale_c => font_hscale_c,
      font_vscale_c => font_vscale_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sof_i => sof_i,
      sol_i => sol_i,
      color_ready_i => color_ready_s,
      color_valid_o => color_valid_s,
      color_o => color_s,

      text_i => text_i,
      color_i => color_i
      );

  colormap: work.colormap.dvi_colormap_lookup
    generic map(
      color_count_l2_c => color_count_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
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
