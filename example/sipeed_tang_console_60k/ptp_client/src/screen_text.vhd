library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_time, nsl_video, work;
use nsl_data.text.all;
use nsl_video.terminal.all;
use nsl_time.calendar.all;
use nsl_time.timestamp.all;
use nsl_time.discipline.all;
use work.screen.all;

-- Composes the slave status as the text and colors of the label
-- screen described by screen_labels_c.
entity screen_text is
  generic(
    utc_offset_c : natural := 37;
    display_utc_c : boolean := false;
    asymmetry_ns_c : integer := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    link_up_i : in std_ulogic;
    locked_i : in std_ulogic;
    second_i : in unsigned(31 downto 0);
    offset_i : in timestamp_nanosecond_offset_t;
    path_delay_i : in timestamp_nanosecond_offset_t;
    freq_ppb_i : in frequency_ppb_t;
    sync_count_i : in unsigned(15 downto 0);
    step_count_i : in unsigned(15 downto 0);
    rx_frames_i : in unsigned(15 downto 0);
    tx_frames_i : in unsigned(15 downto 0);

    text_o : out string(1 to screen_text_length_c);
    colors_o : out label_color_vector(0 to screen_color_count_c-1)
    );
end entity;

architecture beh of screen_text is

  -- Indices in the palette of the top level
  constant color_black_c : label_color_t := x"00";
  constant color_red_c : label_color_t := x"01";
  constant color_green_c : label_color_t := x"02";
  constant color_yellow_c : label_color_t := x"04";
  constant color_cyan_c : label_color_t := x"05";
  constant color_white_c : label_color_t := x"07";

  -- Glyphs of the font beyond ASCII
  constant glyph_heart_c : natural := 16#03#;
  constant glyph_dot_c : natural := 16#07#;
  constant glyph_ring_c : natural := 16#09#;
  constant glyph_up_c : natural := 16#18#;
  constant glyph_down_c : natural := 16#19#;

  function glyph(code : natural) return string
  is
    variable ret : string(1 to 1);
  begin
    ret(1) := character'val(code);
    return ret;
  end function;

  -- Full screen row, the text left aligned.
  function row(s : string) return string
  is
    alias sa : string(1 to s'length) is s;
    variable ret : string(1 to screen_columns_c) := (others => ' ');
  begin
    assert s'length <= screen_columns_c
      report "Row text does not fit"
      severity failure;
    ret(1 to s'length) := sa;
    return ret;
  end function;

  -- Sign and hexadecimal magnitude.  Decimal conversion of wide
  -- values does not fit a cycle.
  function signed_hex(v : signed) return string
  is
    variable magnitude : unsigned(v'length-1 downto 0);
    variable sign : character;
  begin
    if v < 0 then
      sign := '-';
      magnitude := unsigned(-v);
    else
      sign := '+';
      magnitude := unsigned(v);
    end if;
    return sign & to_hex_string(std_ulogic_vector(magnitude));
  end function;

  function hex(v : unsigned) return string
  is
  begin
    return to_hex_string(std_ulogic_vector(v));
  end function;

  -- Green within 100 ns, yellow within a microsecond, red beyond.
  function offset_color(v : signed) return label_color_t
  is
    variable magnitude : signed(v'length downto 0);
  begin
    magnitude := abs(resize(v, v'length + 1));
    if magnitude < 100 then
      return color_green_c;
    elsif magnitude < 1000 then
      return color_yellow_c;
    end if;
    return color_red_c;
  end function;

  function timescale_name return string
  is
  begin
    if display_utc_c then
      return "UTC";
    end if;
    return "TAI";
  end function;

  function displayed_offset return natural
  is
  begin
    if display_utc_c then
      return utc_offset_c;
    end if;
    return 0;
  end function;

  signal displayed_seconds_s : unsigned(31 downto 0);
  signal date_time_s : date_time_t;

begin

  -- The time base counts PTP seconds, TAI on the 1970 epoch.
  displayed_seconds_s <= second_i - to_unsigned(displayed_offset, 32);

  calendar: calendar_from_seconds
    generic map(
      epoch_year_c => 1970
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      seconds_i => displayed_seconds_s,
      date_time_o => date_time_s,
      valid_o => open
      );

  text_o <= if_else(second_i(0) = '1', glyph(glyph_heart_c), " ")
            & "LNK" & if_else(link_up_i = '1', glyph(glyph_up_c), glyph(glyph_down_c))
            & "PTP" & if_else(locked_i = '1', glyph(glyph_dot_c), glyph(glyph_ring_c))
            & "PTP L2 SLAVE"
            & row(to_decimal_string(date_time_s.year, 4) & "-"
                  & to_decimal_string(date_time_s.month, 2) & "-"
                  & to_decimal_string(date_time_s.day, 2) & "  "
                  & to_decimal_string(date_time_s.hour, 2) & ":"
                  & to_decimal_string(date_time_s.minute, 2) & ":"
                  & to_decimal_string(date_time_s.second, 2) & "  "
                  & timescale_name)
            & row("OFFSET " & signed_hex(offset_i) & " ns")
            & row("DELAY  " & signed_hex(path_delay_i) & " ns")
            & row("FREQ   " & signed_hex(freq_ppb_i) & " ppb")
            & row("SYNC " & hex(sync_count_i) & "  STEP " & hex(step_count_i))
            & row("RX   " & hex(rx_frames_i) & "  TX   " & hex(tx_frames_i))
            & row("ASYM   " & integer'image(asymmetry_ns_c) & " ns");

  colors_o(screen_color_background_c) <= color_black_c;
  colors_o(screen_color_value_c) <= color_cyan_c;
  colors_o(screen_color_heart_c) <= color_white_c;
  colors_o(screen_color_link_c) <= color_green_c when link_up_i = '1' else color_red_c;
  colors_o(screen_color_lock_c) <= color_green_c when locked_i = '1' else color_red_c;
  colors_o(screen_color_title_c) <= color_white_c;
  colors_o(screen_color_time_c) <= color_cyan_c when locked_i = '1' else color_yellow_c;
  colors_o(screen_color_offset_c) <= offset_color(offset_i) when locked_i = '1' else color_red_c;

end architecture;
