library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_digilent, nsl_dvi, nsl_color, nsl_indication,
  nsl_time, nsl_data;
use nsl_color.rgb.all;
use nsl_dvi.terminal.all;
use nsl_data.text.all;
use nsl_time.calendar.all;

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;

    j4_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;

  constant color_palette_c : rgb24_vector(0 to 7) := (
    rgb24_black,
    rgb24_red,
    rgb24_lime,
    rgb24_blue,
    rgb24_yellow,
    rgb24_cyan,
    rgb24_magenta,
    rgb24_white);

  -- Color port entries
  constant color_background_c : natural := 0;
  constant color_title_c : natural := 1;
  constant color_value_c : natural := 2;
  constant color_status_c : natural := 3;
  constant color_count_c : natural := 4;

  -- 96x64 panel with 6x8 font: 16 columns, 8 rows
  constant labels_c : label_vector(0 to 6) := (
    text_label(0, 0, 16, color_title_c, color_background_c),
    text_label(2, 0, 6, color_title_c, color_background_c),
    text_label(3, 0, 16, color_value_c, color_background_c),
    text_label(4, 0, 8, color_value_c, color_background_c),
    text_label(6, 0, 6, color_title_c, color_background_c),
    text_label(6, 7, 9, color_value_c, color_background_c),
    text_label(7, 0, 9, color_status_c, color_background_c, underline => true)
    );

  constant text_length_c : natural := labels_text_length(labels_c);

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;
  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;

  signal text_s : string(1 to text_length_c);
  signal colors_s : label_color_vector(0 to color_count_c-1);

  signal tick_counter_s : integer range 0 to clk_hz_c-1 := 0;
  signal seconds_s : unsigned(31 downto 0) := (others => '0');
  -- Frame counter kept as decimal digits, most significant first
  constant frame_digit_count_c : natural := 9;
  type digit_vector is array(0 to frame_digit_count_c-1) of unsigned(3 downto 0);
  signal frame_digits_s : digit_vector := (others => (others => '0'));
  signal frame_toggle_s : unsigned(5 downto 0) := (others => '0');

  function to_string(digits: digit_vector) return string
  is
    variable ret : string(1 to digits'length);
  begin
    for i in digits'range
    loop
      ret(i + 1) := character'val(character'pos('0') + to_integer(digits(i)));
    end loop;
    return ret;
  end function;
  signal date_time_s : date_time_t;

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

  terminal: nsl_dvi.terminal.terminal_labels
    generic map(
      row_count_l2_c => 3,
      column_count_l2_c => 4,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => labels_c,
      blank_color_c => color_background_c,
      underline_support_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sof_i => sof_s,
      sol_i => sol_s,
      pixel_ready_i => pixel_ready_s,
      pixel_valid_o => pixel_valid_s,
      pixel_o => pixel_s,

      text_i => text_s,
      color_i => colors_s
      );

  counters: process(clock_s, reset_n_s)
  begin
    if rising_edge(clock_s) then
      if tick_counter_s /= clk_hz_c - 1 then
        tick_counter_s <= tick_counter_s + 1;
      else
        tick_counter_s <= 0;
        seconds_s <= seconds_s + 1;
      end if;

      if sof_s = '1' then
        frame_toggle_s <= frame_toggle_s + 1;
        for i in frame_digits_s'reverse_range
        loop
          if frame_digits_s(i) /= 9 then
            frame_digits_s(i) <= frame_digits_s(i) + 1;
            exit;
          end if;
          frame_digits_s(i) <= (others => '0');
        end loop;
      end if;
    end if;

    if reset_n_s = '0' then
      tick_counter_s <= 0;
      seconds_s <= (others => '0');
      frame_toggle_s <= (others => '0');
      frame_digits_s <= (others => (others => '0'));
    end if;
  end process;

  -- Uptime shown as a date from the Unix epoch
  calendar: calendar_from_seconds
    generic map(
      epoch_year_c => 1970
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      seconds_i => seconds_s,
      date_time_o => date_time_s
      );

  text_s <= "NSL LABEL SCREEN"
            & "UPTIME"
            & to_decimal_string(date_time_s.year, 4) & "-"
            & to_decimal_string(date_time_s.month, 2) & "-"
            & to_decimal_string(date_time_s.day, 2) & "   UTC"
            & to_decimal_string(date_time_s.hour, 2) & ":"
            & to_decimal_string(date_time_s.minute, 2) & ":"
            & to_decimal_string(date_time_s.second, 2)
            & "FRAMES"
            & to_string(frame_digits_s)
            & "STATUS " & if_else(seconds_s(2) = '0', "ok", "--");

  colors_s(color_background_c) <= x"00";
  colors_s(color_title_c) <= x"07";
  colors_s(color_value_c) <= x"05";
  colors_s(color_status_c) <= x"02" when seconds_s(2) = '0' else x"01";

  done_led_o <= frame_toggle_s(frame_toggle_s'left);

end arch;
