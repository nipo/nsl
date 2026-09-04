library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_digilent, nsl_dvi, nsl_color, nsl_indication;
use nsl_color.rgb.all;

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;

    j4_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;

  -- 96x64 panel with 6x8 font: 16 columns, 8 rows
  constant column_count_c : natural := 16;
  constant row_count_c : natural := 8;

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

  type regs_t is
  record
    row: unsigned(2 downto 0);
    column: unsigned(3 downto 0);
    done: boolean;
  end record;

  signal r, rin : regs_t;

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;
  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;

  signal write_s : std_ulogic;
  signal character_s : unsigned(7 downto 0);
  signal foreground_s : unsigned(2 downto 0);

  signal frame_counter_s : unsigned(5 downto 0) := (others => '0');

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => internal_reset_n_s
      );

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => internal_reset_n_s,
      data_o => reset_n_s
      );

  display: nsl_digilent.pmod_oled_rgb.pmod_oled_rgb_driver
    generic map(
      clock_i_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s,

      pmod_io => j4_io
      );

  terminal: nsl_dvi.terminal.terminal_text_buffer
    generic map(
      row_count_l2_c => 3,
      column_count_l2_c => 4,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
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

  -- Fills the text buffer with the static screen once after reset
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

  -- Refresh heartbeat, toggles about twice a second
  heartbeat: process(clock_s)
  begin
    if rising_edge(clock_s) then
      if sof_s = '1' then
        frame_counter_s <= frame_counter_s + 1;
      end if;
    end if;
  end process;

  done_led_o <= frame_counter_s(frame_counter_s'left);

end arch;
