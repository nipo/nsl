library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking, nsl_hwdep, nsl_digilent, nsl_icesugar, nsl_dvi,
  nsl_color, nsl_indication, nsl_data, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_color.rgb.all;
use nsl_dvi.terminal.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_usb.hid_host.all;

-- USB keyboard monitor: a low-speed HID host on the USB-A port, with
-- link status, device identity and the live boot report shown on the
-- ST7735 LCD on J4.
--
-- Everything runs in a single 12MHz domain (the rate the host engine
-- requires), which puts the LCD SPI clock at 6MHz.
entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;

    j4_io: inout nsl_digilent.pmod.pmod_double_t;

    usb_p_io: inout std_logic;
    usb_n_io: inout std_logic
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;
  constant usb_hz_c : natural := 12_000_000;

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

  constant line_length_c : natural := 26;

  -- 160x80 panel with 6x8 font: 26 columns, 10 rows.  Row 0 is the
  -- live typed line.
  constant labels_c : label_vector(0 to 8) := (
    text_label(0, 0, line_length_c, color_value_c, color_background_c),
    text_label(2, 0, 4, color_title_c, color_background_c),
    text_label(2, 5, 9, color_status_c, color_background_c),
    text_label(3, 0, 4, color_title_c, color_background_c),
    text_label(3, 5, 9, color_value_c, color_background_c),
    text_label(5, 0, 4, color_title_c, color_background_c),
    text_label(5, 5, 8, color_value_c, color_background_c),
    text_label(7, 0, 4, color_title_c, color_background_c),
    text_label(8, 0, 17, color_value_c, color_background_c)
    );

  constant text_length_c : natural := labels_text_length(labels_c);

  -- One letter per modifier bit of the boot report, LSB first:
  -- left/right control, shift, alt, gui.
  function modifiers_string(m: byte) return string
  is
    constant letters_c : string(1 to 8) := "CSAGcsag";
    variable ret : string(1 to 8);
  begin
    for i in 0 to 7
    loop
      if m(i) = '1' then
        ret(i + 1) := letters_c(i + 1);
      else
        ret(i + 1) := '.';
      end if;
    end loop;
    return ret;
  end function;

  signal clk50_s, clock_s, pll_locked_s : std_ulogic;
  signal internal_reset_n_s, merged_reset_n_s, reset_n_s : std_ulogic;
  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;

  signal usb_c_s : nsl_usb.io.usb_io_c;
  signal usb_s_s : nsl_usb.io.usb_io_s;

  signal identity_s : device_identity_t;
  signal status_s : hid_host_status_t;
  signal matched_s : std_ulogic;
  signal modifiers_s : byte;
  signal keys_s : byte_string(0 to 5);
  signal valid_s : std_ulogic;

  signal event_s : keyboard_event_t;
  signal event_valid_s, event_ready_s : std_ulogic;
  signal repeated_s : keyboard_event_t;
  signal repeated_valid_s, repeated_ready_s : std_ulogic;
  signal char_s : nsl_amba.axi4_stream.bus_t;
  signal clear_s : std_ulogic;

  signal text_line_s : string(1 to line_length_c) := (others => ' ');
  signal cursor_s : natural range 0 to line_length_c := 0;

  signal text_s : string(1 to text_length_c);
  signal colors_s : label_color_vector(0 to color_count_c-1);

  signal frame_toggle_s : unsigned(5 downto 0) := (others => '0');

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clk50_s
      );

  pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clk_hz_c,
      output_hz_c => usb_hz_c
      )
    port map(
      clock_i => clk50_s,
      clock_o => clock_s,
      reset_n_i => '1',
      locked_o => pll_locked_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => internal_reset_n_s
      );

  merged_reset_n_s <= internal_reset_n_s and pll_locked_s;

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => merged_reset_n_s,
      data_o => reset_n_s
      );

  keyboard: nsl_usb.hid_host.hid_host_keyboard
    generic map(
      clock_rate_c => usb_hz_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      bus_o => usb_c_s,
      bus_i => usb_s_s,

      identity_o => identity_s,
      status_o => status_s,
      matched_o => matched_s,

      modifiers_o => modifiers_s,
      keys_o => keys_s,
      valid_o => valid_s
      );

  clear_s <= not matched_s;

  events: nsl_usb.hid_host.hid_host_keyboard_events
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      clear_i => clear_s,
      modifiers_i => modifiers_s,
      keys_i => keys_s,
      valid_i => valid_s,
      event_o => event_s,
      valid_o => event_valid_s,
      ready_i => event_ready_s
      );

  repeat: nsl_usb.hid_host.hid_host_keyboard_repeat
    generic map(
      clock_rate_c => usb_hz_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      event_i => event_s,
      valid_i => event_valid_s,
      ready_o => event_ready_s,
      event_o => repeated_s,
      valid_o => repeated_valid_s,
      ready_i => repeated_ready_s
      );

  chars: nsl_usb.hid_host.hid_host_keyboard_chars
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      event_i => repeated_s,
      valid_i => repeated_valid_s,
      ready_o => repeated_ready_s,
      data_o => char_s.m,
      data_i => char_s.s
      );

  char_s.s <= accept(report_cfg_c, true);

  -- Minimal line editor on row 0: printable characters append (the
  -- line scrolls left when full), carriage return clears, backspace
  -- deletes.
  line_editor: process(clock_s, reset_n_s)
    variable code : natural;
  begin
    if rising_edge(clock_s) then
      if is_valid(report_cfg_c, char_s.m) then
        code := to_integer(unsigned(bytes(report_cfg_c, char_s.m)(0)));

        if code = 13 then
          text_line_s <= (others => ' ');
          cursor_s <= 0;
        elsif code = 8 then
          if cursor_s /= 0 then
            text_line_s(cursor_s) <= ' ';
            cursor_s <= cursor_s - 1;
          end if;
        elsif code >= 32 and code <= 126 then
          if cursor_s = line_length_c then
            text_line_s <= text_line_s(2 to line_length_c) & character'val(code);
          else
            text_line_s(cursor_s + 1) <= character'val(code);
            cursor_s <= cursor_s + 1;
          end if;
        end if;
      end if;
    end if;

    if reset_n_s = '0' then
      text_line_s <= (others => ' ');
      cursor_s <= 0;
    end if;
  end process;

  usb_p_io <= usb_c_s.dp when usb_c_s.oe = '1' else 'Z';
  usb_n_io <= usb_c_s.dm when usb_c_s.oe = '1' else 'Z';
  usb_s_s.dp <= usb_p_io;
  usb_s_s.dm <= usb_n_io;

  display: nsl_icesugar.pmod_lcd_096.pmod_lcd_096_driver
    generic map(
      clock_i_hz_c => usb_hz_c
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
      row_count_l2_c => 4,
      column_count_l2_c => 5,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => labels_c,
      blank_color_c => color_background_c
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

  text_s <= text_line_s
            & "LINK"
            & if_else(matched_s = '1', "OK       ",
                      if_else(identity_s.valid, "NOT A KBD", "SEARCHING"))
            & "DEV "
            & to_hex_string(std_ulogic_vector(identity_s.vid)) & ":"
            & to_hex_string(std_ulogic_vector(identity_s.pid))
            & "MOD "
            & modifiers_string(modifiers_s)
            & "KEYS"
            & to_hex_string(keys_s(0)) & " "
            & to_hex_string(keys_s(1)) & " "
            & to_hex_string(keys_s(2)) & " "
            & to_hex_string(keys_s(3)) & " "
            & to_hex_string(keys_s(4)) & " "
            & to_hex_string(keys_s(5));

  colors_s(color_background_c) <= x"00";
  colors_s(color_title_c) <= x"07";
  colors_s(color_value_c) <= x"05";
  colors_s(color_status_c) <= x"02" when matched_s = '1' else x"01";

  heartbeat: process(clock_s)
  begin
    if rising_edge(clock_s) then
      if sof_s = '1' then
        frame_toggle_s <= frame_toggle_s + 1;
      end if;
    end if;
  end process;

  done_led_o <= frame_toggle_s(frame_toggle_s'left);

end arch;
