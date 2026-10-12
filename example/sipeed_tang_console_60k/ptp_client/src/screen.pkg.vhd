library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_time, nsl_video;
use nsl_video.terminal.all;

package screen is

  -- Label screen layout on the 26x10 terminal of a 160x80 panel: a
  -- status row of glyphs, each with its own color, then one value
  -- per row.
  constant screen_columns_c : natural := 26;

  constant screen_color_background_c : natural := 0;
  constant screen_color_value_c : natural := 1;
  constant screen_color_heart_c : natural := 2;
  constant screen_color_link_c : natural := 3;
  constant screen_color_lock_c : natural := 4;
  constant screen_color_title_c : natural := 5;
  constant screen_color_time_c : natural := 6;
  constant screen_color_offset_c : natural := 7;
  constant screen_color_count_c : natural := 8;

  constant screen_labels_c : label_vector(0 to 10) := (
    text_label(0, 0, 1, screen_color_heart_c, screen_color_background_c),
    text_label(0, 2, 4, screen_color_link_c, screen_color_background_c),
    text_label(0, 7, 4, screen_color_lock_c, screen_color_background_c),
    text_label(0, 14, 12, screen_color_title_c, screen_color_background_c),
    text_label(1, 0, screen_columns_c, screen_color_time_c, screen_color_background_c),
    text_label(2, 0, screen_columns_c, screen_color_offset_c, screen_color_background_c),
    text_label(3, 0, screen_columns_c, screen_color_value_c, screen_color_background_c),
    text_label(4, 0, screen_columns_c, screen_color_value_c, screen_color_background_c),
    text_label(5, 0, screen_columns_c, screen_color_value_c, screen_color_background_c),
    text_label(6, 0, screen_columns_c, screen_color_value_c, screen_color_background_c),
    text_label(7, 0, screen_columns_c, screen_color_value_c, screen_color_background_c)
    );

  constant screen_text_length_c : natural := labels_text_length(screen_labels_c);

  component screen_text is
    generic(
      -- TAI minus UTC, in seconds, taken off the time base for display
      -- when display_utc_c is set.
      utc_offset_c : natural := 37;
      display_utc_c : boolean := false;
      -- Shown as configured, for reference.
      asymmetry_ns_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      link_up_i : in std_ulogic;
      locked_i : in std_ulogic;
      -- Time base second, PTP timescale.
      second_i : in unsigned(31 downto 0);
      -- Last offset handed to the servo, asymmetry corrected.
      offset_i : in nsl_time.timestamp.timestamp_nanosecond_offset_t;
      path_delay_i : in nsl_time.timestamp.timestamp_nanosecond_offset_t;
      freq_ppb_i : in nsl_time.discipline.frequency_ppb_t;
      sync_count_i : in unsigned(15 downto 0);
      step_count_i : in unsigned(15 downto 0);
      rx_frames_i : in unsigned(15 downto 0);
      tx_frames_i : in unsigned(15 downto 0);

      -- Label screen contents, laid out as screen_labels_c
      text_o : out string(1 to screen_text_length_c);
      colors_o : out label_color_vector(0 to screen_color_count_c-1)
      );
  end component;

end package;
