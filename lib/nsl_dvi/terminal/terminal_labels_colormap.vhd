library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_indication, work;
use nsl_data.bytestream.all;
use work.terminal.all;

entity terminal_labels_colormap is
  generic(
    row_count_l2_c: positive;
    column_count_l2_c: positive;
    character_count_l2_c : positive;
    color_count_l2_c : natural;
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
    color_ready_i : in std_ulogic;
    color_valid_o : out std_ulogic;
    color_o : out unsigned(color_count_l2_c-1 downto 0);

    text_i : in string;
    color_i : in label_color_vector
    );
end entity;

architecture beh of terminal_labels_colormap is

  constant layout_c: layout_cell_vector(0 to 2**(row_count_l2_c+column_count_l2_c)-1)
    := layout_build(labels_c, row_count_l2_c, column_count_l2_c, blank_color_c);

  subtype character_t is unsigned(character_count_l2_c-1 downto 0);
  subtype color_index_t is unsigned(color_count_l2_c-1 downto 0);

  signal text_bytes_s: byte_string(0 to text_i'length-1);
  signal colors_s: label_color_vector(0 to color_i'length-1);

  signal cell_enable_s: std_ulogic;
  signal cell_row_s: unsigned(row_count_l2_c-1 downto 0);
  signal cell_column_s: unsigned(column_count_l2_c-1 downto 0);

  signal cell_character_s: character_t;
  signal cell_underline_s: std_ulogic;
  signal cell_foreground_s, cell_background_s: color_index_t;

begin

  assert labels_text_length(labels_c) = text_i'length
    report "Text length " & integer'image(text_i'length)
    & " does not match labels total length "
    & integer'image(labels_text_length(labels_c))
    severity failure;

  assert labels_color_count(labels_c, blank_color_c) <= color_i'length
    report "Labels refer to " & integer'image(labels_color_count(labels_c, blank_color_c))
    & " colors, only " & integer'image(color_i'length) & " are given"
    severity failure;

  text_bytes_s <= to_byte_string(text_i);
  colors_s <= color_i;

  composer: process(clock_i) is
    variable cell: layout_cell_t;
  begin
    if rising_edge(clock_i) then
      if cell_enable_s = '1' then
        cell := layout_c(to_integer(cell_row_s & cell_column_s));

        if cell.text then
          cell_character_s <= resize(unsigned(text_bytes_s(cell.text_index)), character_t'length);
        else
          cell_character_s <= to_unsigned(blank_character_c, character_t'length);
        end if;

        cell_foreground_s <= resize(colors_s(cell.foreground), color_index_t'length);
        cell_background_s <= resize(colors_s(cell.background), color_index_t'length);

        if cell.underline then
          cell_underline_s <= '1';
        else
          cell_underline_s <= '0';
        end if;
      end if;
    end if;
  end process;

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
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sof_i => sof_i,
      sol_i => sol_i,
      color_ready_i => color_ready_i,
      color_valid_o => color_valid_o,
      color_o => color_o,

      cell_enable_o => cell_enable_s,
      cell_row_o => cell_row_s,
      cell_column_o => cell_column_s,
      cell_character_i => cell_character_s,
      cell_underline_i => cell_underline_s,
      cell_foreground_i => cell_foreground_s,
      cell_background_i => cell_background_s
      );

end architecture;
