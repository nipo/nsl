library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_dvi, nsl_time, work;
use nsl_data.text.all;
use nsl_dvi.terminal.all;
use nsl_time.calendar.all;
use nsl_time.timestamp.all;
use nsl_time.discipline.all;
use work.func.all;

-- Composes the grandmaster status as the text and colors of the label
-- screen described by screen_labels_c.
entity screen_text is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    link_up_i : in std_ulogic;
    gps_locked_i : in std_ulogic;
    local_tick_i : in std_ulogic;
    gps_tick_i : in std_ulogic;
    second_i : in unsigned(31 downto 0);
    utc_offset_i : in signed(15 downto 0);
    utc_offset_valid_i : in std_ulogic;
    pps_offset_i : in timestamp_nanosecond_offset_t;
    aux_offset_i : in timestamp_nanosecond_offset_t;
    freq_ppb_i : in frequency_ppb_t;
    tacc_i : in unsigned(31 downto 0);
    clock_class_i : in unsigned(7 downto 0);
    dac_i : in unsigned(11 downto 0);

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

  -- Sign and digits, the magnitude saturated to what the digits hold.
  function signed_decimal(v : signed; digit_count : positive) return string
  is
    constant max_c : unsigned(31 downto 0)
      := to_unsigned(10 ** digit_count - 1, 32);
    variable wide : signed(32 downto 0);
    variable magnitude : unsigned(31 downto 0);
    variable sign : character;
  begin
    wide := resize(v, 33);
    if wide < 0 then
      sign := '-';
      wide := -wide;
    else
      sign := '+';
    end if;
    magnitude := unsigned(wide(31 downto 0));
    if magnitude > max_c then
      magnitude := max_c;
    end if;
    return sign & to_decimal_string(magnitude, digit_count);
  end function;

  function saturated(v : unsigned; digit_count : positive) return string
  is
    constant max_c : unsigned(31 downto 0)
      := to_unsigned(10 ** digit_count - 1, 32);
    variable magnitude : unsigned(31 downto 0);
  begin
    magnitude := resize(v, 32);
    if magnitude > max_c then
      magnitude := max_c;
    end if;
    return to_decimal_string(magnitude, digit_count);
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

  signal utc_seconds_s : unsigned(31 downto 0);
  signal date_time_s : date_time_t;
  -- Heartbeat on the local second, keepalive on the receiver's pulse.
  signal heart_s, pulse_s : std_ulogic;

begin

  liveness: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if local_tick_i = '1' then
        heart_s <= not heart_s;
      end if;
      if gps_tick_i = '1' then
        pulse_s <= not pulse_s;
      end if;
    end if;

    if reset_n_i = '0' then
      heart_s <= '0';
      pulse_s <= '0';
    end if;
  end process;

  -- The time base counts PTP seconds, TAI on the 1970 epoch; the
  -- announced offset brings it back to UTC.
  utc_seconds_s <= unsigned(signed(second_i) - resize(utc_offset_i, 32));

  calendar: calendar_from_seconds
    generic map(
      epoch_year_c => 1970
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      seconds_i => utc_seconds_s,
      date_time_o => date_time_s
      );

  text_o <= if_else(heart_s = '1', glyph(glyph_heart_c), " ")
            & "LNK" & if_else(link_up_i = '1', glyph(glyph_up_c), glyph(glyph_down_c))
            & "GPS" & if_else(gps_locked_i = '1', glyph(glyph_dot_c), glyph(glyph_ring_c))
            & "PPS" & if_else(pulse_s = '1', glyph(glyph_dot_c), glyph(glyph_ring_c))
            & to_decimal_string(date_time_s.year, 4) & "-"
            & to_decimal_string(date_time_s.month, 2) & "-"
            & to_decimal_string(date_time_s.day, 2) & "   UTC"
            & to_decimal_string(date_time_s.hour, 2) & ":"
            & to_decimal_string(date_time_s.minute, 2) & ":"
            & to_decimal_string(date_time_s.second, 2) & "  TAI"
            & signed_decimal(utc_offset_i, 2)
            & "PPS  " & signed_decimal(pps_offset_i, 6) & " ns "
            & "AUX  " & signed_decimal(aux_offset_i, 6) & " ns "
            & "SERVO " & signed_decimal(freq_ppb_i, 5) & " ppb"
            & "TACC " & saturated(tacc_i, 6) & " ns  "
            & "CLS " & saturated(clock_class_i, 3) & " DAC "
            & to_hex_string(std_ulogic_vector(resize(dac_i, 16)));

  colors_o(screen_color_background_c) <= color_black_c;
  colors_o(screen_color_value_c) <= color_cyan_c;
  colors_o(screen_color_heart_c) <= color_white_c;
  colors_o(screen_color_link_c) <= color_green_c when link_up_i = '1' else color_red_c;
  colors_o(screen_color_gps_c) <= color_green_c when gps_locked_i = '1' else color_red_c;
  colors_o(screen_color_pulse_c) <= color_green_c when gps_locked_i = '1' else color_yellow_c;
  colors_o(screen_color_time_c) <= color_cyan_c when utc_offset_valid_i = '1' else color_yellow_c;
  colors_o(screen_color_pps_c) <= offset_color(pps_offset_i);
  colors_o(screen_color_tacc_c) <= offset_color(signed(resize(tacc_i, 32)));
  colors_o(screen_color_class_c) <=
    color_green_c when clock_class_i = to_unsigned(6, 8)
    else color_yellow_c when clock_class_i = to_unsigned(7, 8)
    else color_red_c;

end architecture;
