library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_indication, nsl_color, nsl_simulation, nsl_data;
use nsl_video.terminal.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;
use nsl_indication.font.all;
use nsl_indication.font_6x8.all;

-- Renders two frames of a label screen through terminal_labels and
-- checks every pixel against a reference computed from the font and
-- an independent walk of the label list.
entity tb is
end entity;

architecture sim of tb is

  constant clock_period_c : time := 10 ns;

  constant column_count_c : natural := 16;
  constant row_count_c : natural := 8;
  constant font_width_c : natural := 6;
  constant font_height_c : natural := 8;
  constant width_c : natural := column_count_c * font_width_c;
  constant height_c : natural := row_count_c * font_height_c;

  constant color_palette_c : rgb24_vector(0 to 7) := (
    rgb24_black,
    rgb24_red,
    rgb24_lime,
    rgb24_blue,
    rgb24_yellow,
    rgb24_cyan,
    rgb24_magenta,
    rgb24_white);

  -- Color port entries: 0 black, 1 red, 2 lime, 3 blue, 4 status, 5 white
  constant labels_c : label_vector(0 to 4) := (
    text_label(0, 0, 10, 5, 0),
    text_label(1, 3, 3, 1, 0),
    text_label(2, 0, 5, 2, 3),
    text_label(5, 0, 16, 5, 0),
    text_label(7, 4, 6, 4, 0, underline => true)
    );

  constant text_length_c : natural := labels_text_length(labels_c);
  constant blank_color_c : natural := 0;

  constant text_1_c : string(1 to text_length_c)
    := "NSL LABELS" & "RED" & "GREEN" & "0123456789ABCDEF" & "STATUS";
  constant text_2_c : string(1 to text_length_c)
    := "TWO LABELS" & "red" & "green" & "FEDCBA9876543210" & "status";

  constant colors_1_c : label_color_vector(0 to 5)
    := (x"00", x"01", x"02", x"03", x"07", x"07");
  constant colors_2_c : label_color_vector(0 to 5)
    := (x"00", x"01", x"02", x"03", x"04", x"07");

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  constant config_c : config_t := config(pixels => 1);

  signal out_s : bus_t;
  signal valid_s : std_ulogic;

  signal text_s : string(1 to text_length_c);
  signal colors_s : label_color_vector(0 to 5);

  signal done_s : boolean := false;

  function to_hex_string(c: rgb24) return string is
  begin
    return to_hex_string(std_ulogic_vector(c.r))
      & to_hex_string(std_ulogic_vector(c.g))
      & to_hex_string(std_ulogic_vector(c.b));
  end function;

  function expected_pixel(x, y: natural;
                          text: string;
                          colors: label_color_vector) return rgb24 is
    constant row : natural := y / font_height_c;
    constant column : natural := x / font_width_c;
    constant glyph_line : natural := y mod font_height_c;
    variable text_index : natural := 0;
    variable ch : natural := 32;
    variable fg, bg : natural := blank_color_c;
    variable underline : boolean := false;
    variable line : std_ulogic_vector(0 to font_width_c - 1);
  begin
    for i in labels_c'range loop
      if labels_c(i).row = row
        and column >= labels_c(i).column
        and column < labels_c(i).column + labels_c(i).length then
        ch := character'pos(text(text'low + text_index + column - labels_c(i).column));
        fg := labels_c(i).foreground;
        bg := labels_c(i).background;
        underline := labels_c(i).underline;
      end if;
      text_index := text_index + labels_c(i).length;
    end loop;

    line := font_glyph_line_get(font_6x8_c, ch, glyph_line);
    if underline and glyph_line = font_height_c - 1 then
      line := not line;
    end if;

    if line(x mod font_width_c) = '1' then
      return color_palette_c(to_integer(colors(fg)));
    else
      return color_palette_c(to_integer(colors(bg)));
    end if;
  end function;

begin

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 10 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  dut: terminal_labels
    generic map(
      row_count_l2_c => 3,
      column_count_l2_c => 4,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => font_6x8_c,
      labels_c => labels_c,
      blank_color_c => blank_color_c,
      underline_support_c => true,
      config_c => config_c,
      geometry_c => terminal_geometry(font_6x8_c, 4, 3)
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      out_o => out_s.m,
      out_i => out_s.s,

      text_i => text_s,
      color_i => colors_s
      );

  valid_s <= '1' when is_valid(config_c, out_s.m) else '0';

  driver: process is
    variable color_v: rgb24;
    variable sof_v, last_v, eof_v: boolean;

    -- Takes one beat, ready_period cycles after the previous one, so
    -- backpressure is exercised.
    procedure take(constant ready_period: positive) is
    begin
      for i in 2 to ready_period loop
        wait until rising_edge(clock_s);
      end loop;
      out_s.s <= accept(config_c, ready => true);
      wait until rising_edge(clock_s) and valid_s = '1';
      color_v := to_rgb24(config_c, pixel(config_c, out_s.m));
      sof_v := is_sof(config_c, out_s.m);
      last_v := is_last(config_c, out_s.m);
      eof_v := is_eof(config_c, out_s.m);
      out_s.s <= accept(config_c, ready => false);
    end procedure;

    -- Drops beats until a frame closes, so the next one is whole.
    procedure drop_frame is
    begin
      loop
        take(1);
        exit when eof_v;
      end loop;
    end procedure;

    -- Pops one frame and checks it, framing bits included.
    procedure check_frame(constant text: string;
                          constant colors: label_color_vector;
                          constant ready_period: positive;
                          constant msg: string) is
      variable expected: rgb24;
    begin
      for y in 0 to height_c - 1 loop
        for x in 0 to width_c - 1 loop
          take(ready_period);

          assert sof_v = (x = 0 and y = 0)
            report msg & ": pixel " & integer'image(x) & "," & integer'image(y)
            & " disagrees on opening the frame"
            severity failure;
          assert last_v = (x = width_c - 1)
            report msg & ": pixel " & integer'image(x) & "," & integer'image(y)
            & " disagrees on closing the line"
            severity failure;
          assert eof_v = (x = width_c - 1 and y = height_c - 1)
            report msg & ": pixel " & integer'image(x) & "," & integer'image(y)
            & " disagrees on closing the frame"
            severity failure;

          expected := expected_pixel(x, y, text, colors);
          assert color_v = expected
            report msg & ": pixel " & integer'image(x) & "," & integer'image(y)
            & " expected " & to_hex_string(expected) & ", got " & to_hex_string(color_v)
            severity failure;
        end loop;
      end loop;
    end procedure;
  begin
    out_s.s <= accept(config_c, ready => false);
    text_s <= text_1_c;
    colors_s <= colors_1_c;

    wait until reset_n_s = '1';

    -- The generator runs its own raster, so land on a frame boundary
    -- before checking one.
    drop_frame;
    check_frame(text_1_c, colors_1_c, 1, "frame 1");

    -- Text is sampled as the screen is scanned, so a change costs at
    -- most one torn frame.
    text_s <= text_2_c;
    colors_s <= colors_2_c;
    drop_frame;

    check_frame(text_2_c, colors_2_c, 3, "frame 2");

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 100 ms;
    assert false
      report "Timeout"
      severity failure;
  end process;

end architecture;
