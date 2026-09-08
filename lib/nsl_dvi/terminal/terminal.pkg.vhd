library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_indication, nsl_math;

package terminal is

  -- A label is a run of characters on one row of the screen. Labels
  -- take their text sequentially from one string: the first label
  -- gets the first `length` characters, the next label the following
  -- ones, and so on. Colors are indices in a color vector port.
  type label_t is
  record
    row, column: natural;
    length: natural;
    foreground, background: natural;
    underline: boolean;
  end record;
  type label_vector is array(natural range <>) of label_t;

  function text_label(row, column, length, foreground, background: natural;
                      underline: boolean := false) return label_t;

  -- Element of the color vector port. Only the low color_count_l2_c
  -- bits are used.
  subtype label_color_t is unsigned(7 downto 0);
  type label_color_vector is array(natural range <>) of label_color_t;

  -- Total count of characters taken from the text by a label vector
  function labels_text_length(labels: label_vector) return natural;
  -- Count of color port entries a label vector and blank color refer to
  function labels_color_count(labels: label_vector; blank_color: natural) return natural;

  -- Screen cell description resolved from a label vector, indexed by
  -- row & column.
  type layout_cell_t is
  record
    text: boolean;
    text_index: natural;
    foreground, background: natural;
    underline: boolean;
  end record;
  type layout_cell_vector is array(natural range <>) of layout_cell_t;

  function layout_build(labels: label_vector;
                        row_count_l2, column_count_l2: natural;
                        blank_color: natural) return layout_cell_vector;

  -- Frame generation part of the text terminal.
  --
  -- Scans a screen of cells in raster order, one glyph line at a
  -- time, fetches cell contents through a memory-like read port, and
  -- renders pixels as color indices. Cell contents must appear
  -- cell_latency_c cycles after cell_row_o/cell_column_o are
  -- presented with cell_enable_o asserted.
  component terminal_frame_generator is
    generic(
      row_count_l2_c: positive;
      column_count_l2_c: positive;
      character_count_l2_c : positive;
      color_count_l2_c : natural;
      font_c: nsl_indication.font.font_t;
      underline_support_c: boolean := false;
      font_hscale_c: positive := 1;
      font_vscale_c: positive := 1;
      cell_latency_c: natural := 1
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      color_ready_i : in std_ulogic;
      color_valid_o : out std_ulogic;
      color_o : out unsigned(color_count_l2_c-1 downto 0);

      cell_enable_o : out std_ulogic;
      cell_row_o : out unsigned(row_count_l2_c-1 downto 0);
      cell_column_o : out unsigned(column_count_l2_c-1 downto 0);
      cell_character_i : in unsigned(character_count_l2_c-1 downto 0);
      cell_underline_i : in std_ulogic := '0';
      cell_foreground_i : in unsigned(color_count_l2_c-1 downto 0);
      cell_background_i : in unsigned(color_count_l2_c-1 downto 0)
      );
  end component;

  -- Label screen generator, with color indices output.
  --
  -- Screen layout is constant, given by labels_c. Text and colors are
  -- ports: text_i must be exactly labels_text_length(labels_c)
  -- characters long, color_i must have at least
  -- labels_color_count(labels_c, blank_color_c) entries. Cells not
  -- covered by any label show blank_character_c with both colors
  -- taken from color_i(blank_color_c).
  --
  -- text_i and color_i are sampled in clock_i domain as the screen is
  -- scanned. A change in the middle of a frame yields at most one
  -- torn frame.
  component terminal_labels_colormap is
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
  end component;

  -- Same as previous, with colormap lookup
  component terminal_labels is
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
  end component;

  -- DVI text terminal generator.
  --
  -- This generates an image for a constant font, a constant palette,
  -- and a dynamic character, foreground / background colors and
  -- underline.
  component terminal_text_buffer_colormap is
    generic(
      -- Terminal dimensions (always a power of two in both
      -- dimensions, even if it overflows the display).
      row_count_l2_c: positive;
      column_count_l2_c: positive;

      -- Count of characters in font
      character_count_l2_c : positive;

      -- Should contain a power-of-two number of entries.  Used as a
      -- zero-based ascending vector where index is color number.
      color_count_l2_c : natural;

      -- A font, as defined in nsl_indication.font
      font_c: nsl_indication.font.font_t;

      -- Whether to support adding underline to characters. This costs
      -- one extra bit in the display memory.  When asserted,
      -- underline inverts the last line of character glyph.
      underline_support_c: boolean := false;

      -- Font scaling (each pixel from font is spread x times in rows
      -- and columns).
      font_hscale_c: positive := 1;
      font_vscale_c: positive := 1
      );
    port(
      -- Display side
      video_clock_i : in  std_ulogic;
      video_reset_n_i : in std_ulogic;

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      color_ready_i : in std_ulogic;
      color_valid_o : out std_ulogic;
      color_o : out unsigned(color_count_l2_c-1 downto 0);

      -- User side. All subsequent IOs clocked by term_clock
      term_clock_i : in  std_ulogic;
      term_reset_n_i : in std_ulogic;

      -- Added to the video-side scan row, modulo the buffer height,
      -- turning the buffer into a ring. Sampled once per frame.
      row_offset_i : in unsigned(row_count_l2_c-1 downto 0) := (others => '0');

      -- Address port to the character memory
      row_i : in unsigned(row_count_l2_c-1 downto 0);
      column_i : in unsigned(column_count_l2_c-1 downto 0);

      enable_i : in std_ulogic;

      -- Write port
      write_i : in std_ulogic;
      character_i : in unsigned(character_count_l2_c-1 downto 0);
      underline_i : in std_ulogic := '0';
      foreground_i : in unsigned(color_count_l2_c-1 downto 0);
      background_i : in unsigned(color_count_l2_c-1 downto 0);

      -- Read port. Response appears the following cycle after
      -- assertion of enable_i.
      character_o : out unsigned(character_count_l2_c-1 downto 0);
      underline_o : out std_ulogic;
      foreground_o : out unsigned(color_count_l2_c-1 downto 0);
      background_o : out unsigned(color_count_l2_c-1 downto 0)
      );
  end component;

  -- Same as previous, with colormap lookup
  component terminal_text_buffer is
    generic(
      row_count_l2_c: positive;
      column_count_l2_c: positive;
      character_count_l2_c : positive;
      color_palette_c : nsl_color.rgb.rgb24_vector;
      font_c: nsl_indication.font.font_t;
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

      row_offset_i : in unsigned(row_count_l2_c-1 downto 0) := (others => '0');

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
  end component;

end package;

package body terminal is

  function text_label(row, column, length, foreground, background: natural;
                      underline: boolean := false) return label_t
  is
  begin
    return label_t'(
      row => row,
      column => column,
      length => length,
      foreground => foreground,
      background => background,
      underline => underline);
  end function;

  function labels_text_length(labels: label_vector) return natural
  is
    variable ret: natural := 0;
  begin
    for i in labels'range
    loop
      ret := ret + labels(i).length;
    end loop;
    return ret;
  end function;

  function labels_color_count(labels: label_vector; blank_color: natural) return natural
  is
    variable ret: natural := blank_color + 1;
  begin
    for i in labels'range
    loop
      if labels(i).foreground + 1 > ret then
        ret := labels(i).foreground + 1;
      end if;
      if labels(i).background + 1 > ret then
        ret := labels(i).background + 1;
      end if;
    end loop;
    return ret;
  end function;

  function layout_build(labels: label_vector;
                        row_count_l2, column_count_l2: natural;
                        blank_color: natural) return layout_cell_vector
  is
    constant column_count: natural := 2 ** column_count_l2;
    constant row_count: natural := 2 ** row_count_l2;
    variable ret: layout_cell_vector(0 to row_count * column_count - 1);
    variable text_index: natural := 0;
    variable cell: natural;
  begin
    for i in ret'range
    loop
      ret(i) := layout_cell_t'(
        text => false,
        text_index => 0,
        foreground => blank_color,
        background => blank_color,
        underline => false);
    end loop;

    for i in labels'range
    loop
      assert labels(i).row < row_count
        report "Label " & integer'image(i) & " row is off screen"
        severity failure;
      assert labels(i).column + labels(i).length <= column_count
        report "Label " & integer'image(i) & " does not fit in its row"
        severity failure;

      for c in 0 to labels(i).length - 1
      loop
        cell := labels(i).row * column_count + labels(i).column + c;
        assert not ret(cell).text
          report "Label " & integer'image(i) & " overlaps another label"
          severity failure;
        ret(cell) := layout_cell_t'(
          text => true,
          text_index => text_index + c,
          foreground => labels(i).foreground,
          background => labels(i).background,
          underline => labels(i).underline);
      end loop;
      text_index := text_index + labels(i).length;
    end loop;

    return ret;
  end function;

end package body;
