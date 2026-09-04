library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_solomonsystech, nsl_dvi, nsl_indication, nsl_spi, nsl_color, nsl_data, nsl_simulation;
use nsl_solomonsystech.ssd1331.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;
use nsl_indication.font.all;
use nsl_indication.font_6x8.all;

-- Renders a static text screen through terminal_text_buffer into the
-- SSD1331 driver and checks every streamed pixel against a reference
-- image computed from the font.
entity tb is
end entity;

architecture sim of tb is

  constant clock_hz_c : natural := 1_000_000;
  constant spi_hz_c : natural := 250_000;
  constant clock_period_c : time := 1 us;

  constant column_count_c : natural := 16;
  constant row_count_c : natural := 8;
  constant font_width_c : natural := 6;
  constant font_height_c : natural := 8;

  constant color_palette_c : rgb24_vector(0 to 7) := (
    rgb24_black,
    rgb24_red,
    rgb24_lime,
    rgb24_blue,
    rgb24_yellow,
    rgb24_cyan,
    rgb24_magenta,
    rgb24_white);

  constant screen_c : string(1 to row_count_c * column_count_c) :=
    "NSL SSD1331     "
    & "RED             "
    & "GREEN           "
    & "BLUE            "
    & "                "
    & "0123456789ABCDEF"
    & "                "
    & "+BOTTOM LEFT    ";

  type row_color_t is array(0 to row_count_c - 1) of natural range 0 to 7;
  constant foreground_c : row_color_t := (7, 1, 2, 3, 7, 7, 7, 4);

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal spi_s : nsl_spi.spi.spi_slave_i;
  signal dc_s, panel_reset_n_s, vcc_en_s, power_en_s : std_ulogic;

  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;

  signal write_s : std_ulogic;
  signal character_s : unsigned(7 downto 0);
  signal foreground_s : unsigned(2 downto 0);

  type regs_t is
  record
    row: unsigned(2 downto 0);
    column: unsigned(3 downto 0);
    done: boolean;
  end record;

  signal r, rin : regs_t;

  signal done_s : boolean := false;

  function expected_pixel(x, y: natural) return rgb24 is
    constant ch : natural
      := character'pos(screen_c((y / font_height_c) * column_count_c
                                + (x / font_width_c) + 1));
    constant line_c : std_ulogic_vector(0 to font_width_c - 1)
      := font_glyph_line_get(font_6x8_c, ch, y mod font_height_c);
  begin
    if line_c(x mod font_width_c) = '1' then
      return color_palette_c(foreground_c(y / font_height_c));
    else
      return color_palette_c(0);
    end if;
  end function;

  function rgb565_msb(c: rgb24) return byte is
  begin
    return std_ulogic_vector(c.r(7 downto 3)) & std_ulogic_vector(c.g(7 downto 5));
  end function;

  function rgb565_lsb(c: rgb24) return byte is
  begin
    return std_ulogic_vector(c.g(4 downto 2)) & std_ulogic_vector(c.b(7 downto 3));
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

  dut: ssd1331_spi_driver
    generic map(
      clock_i_hz_c => clock_hz_c,
      spi_hz_c => spi_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      spi_o => spi_s,
      dc_o => dc_s,
      reset_n_o => panel_reset_n_s,
      vcc_en_o => vcc_en_s,
      power_en_o => power_en_s,

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s
      );

  terminal: nsl_dvi.terminal.terminal_text_buffer
    generic map(
      row_count_l2_c => 3,
      column_count_l2_c => 4,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => font_6x8_c,
      underline_support_c => false,
      font_hscale_c => 1,
      font_vscale_c => 1
      )
    port map(
      video_clock_i => clock_s,
      video_reset_n_i => reset_n_s,

      sof_i => sof_s,
      sol_i => sol_s,
      pixel_ready_i => pixel_ready_s,
      pixel_valid_o => pixel_valid_s,
      pixel_o => pixel_s,

      term_clock_i => clock_s,
      term_reset_n_i => reset_n_s,

      row_i => r.row,
      column_i => r.column,
      enable_i => write_s,
      write_i => write_s,
      character_i => character_s,
      foreground_i => foreground_s,
      background_i => "000"
      );

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.row <= (others => '0');
      r.column <= (others => '0');
      r.done <= false;
    end if;
  end process;

  transition: process(r) is
  begin
    rin <= r;

    if not r.done then
      if r.column /= column_count_c - 1 then
        rin.column <= r.column + 1;
      elsif r.row /= row_count_c - 1 then
        rin.column <= (others => '0');
        rin.row <= r.row + 1;
      else
        rin.done <= true;
      end if;
    end if;
  end process;

  write_s <= '0' when r.done else '1';
  character_s <= to_unsigned(
    character'pos(screen_c(to_integer(unsigned'(r.row & r.column)) + 1)), 8);
  foreground_s <= to_unsigned(foreground_c(to_integer(r.row)), 3);

  monitor: process is
    procedure expect(constant v: byte;
                     constant dc: std_ulogic;
                     constant msg: string) is
      variable sh: byte;
    begin
      for i in 0 to 7 loop
        wait until rising_edge(spi_s.sck);
        assert spi_s.cs_n = '0'
          report msg & ": CS released mid-byte"
          severity failure;
        sh := sh(6 downto 0) & spi_s.mosi;
      end loop;
      assert dc_s = dc
        report msg & ": bad D/C"
        severity failure;
      assert sh = v
        report msg & ": expected " & integer'image(to_integer(unsigned(v)))
        & ", got " & integer'image(to_integer(unsigned(sh)))
        severity failure;
    end procedure;

    procedure expect_setup(constant msg: string) is
    begin
      expect(cmd_column_setup, '0', msg & " column setup");
      expect(x"00", '0', msg & " column start");
      expect(x"5f", '0', msg & " column end");
      expect(cmd_row_setup, '0', msg & " row setup");
      expect(x"00", '0', msg & " row start");
      expect(x"3f", '0', msg & " row end");
    end procedure;

    variable c: rgb24;
  begin
    for i in init_sequence_c'range loop
      expect(init_sequence_c(i), '0', "init byte " & integer'image(i));
    end loop;

    expect_setup("frame 1");
    for y in 0 to max_height_c - 1 loop
      for x in 0 to max_width_c - 1 loop
        c := expected_pixel(x, y);
        expect(rgb565_msb(c), '1', "pixel msb "
               & integer'image(x) & "," & integer'image(y));
        expect(rgb565_lsb(c), '1', "pixel lsb "
               & integer'image(x) & "," & integer'image(y));
      end loop;
    end loop;

    -- Display-on proves the whole first frame was streamed
    expect(cmd_display_on_normal, '0', "display on");

    -- Second frame must render identically from its first line on
    expect_setup("frame 2");
    for x in 0 to max_width_c - 1 loop
      c := expected_pixel(x, 0);
      expect(rgb565_msb(c), '1', "frame 2 pixel msb " & integer'image(x));
      expect(rgb565_lsb(c), '1', "frame 2 pixel lsb " & integer'image(x));
    end loop;

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 sec;
    assert false
      report "Timeout"
      severity failure;
  end process;

end architecture;
