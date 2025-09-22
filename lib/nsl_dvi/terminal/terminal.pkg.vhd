library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_indication, nsl_math;

package terminal is

  -- DVI text terminal generator.
  --
  -- This generates an image for a constant font, a constant palette,
  -- and a dynamic character, foreground / background colors and
  -- underline.
  component terminal_text_buffer is
    generic(
      -- Terminal dimensions (always a power of two in both
      -- dimensions, even if it overflows the display).
      row_count_l2_c: positive;
      column_count_l2_c: positive;

      -- Count of characters in font
      character_count_l2_c : positive;

      -- Should contain a power-of-two number of entries.  Used as a
      -- zero-based ascending vector where index is color number.
      color_palette_c : nsl_color.rgb.rgb24_vector;

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
      pixel_ready_i : in std_ulogic;
      pixel_o : out nsl_color.rgb.rgb24;

      -- User side. All subsequent IOs clocked by term_clock
      term_clock_i : in  std_ulogic;
      term_reset_n_i : in std_ulogic;

      -- Address port to the character memory
      row_i : in unsigned(row_count_l2_c-1 downto 0);
      column_i : in unsigned(column_count_l2_c-1 downto 0);

      enable_i : in std_ulogic;

      -- Write port
      write_i : in std_ulogic;
      character_i : in unsigned(character_count_l2_c-1 downto 0);
      underline_i : in std_ulogic := '0';
      foreground_i : in unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
      background_i : in unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);

      -- Read port. Response appears the following cycle after
      -- assertion of enable_i.
      character_o : out unsigned(character_count_l2_c-1 downto 0);
      underline_o : out std_ulogic;
      foreground_o : out unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
      background_o : out unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0)
      );
  end component;

end package;
