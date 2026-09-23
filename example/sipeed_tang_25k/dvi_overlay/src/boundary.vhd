library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_dvi, nsl_i2c, nsl_video, nsl_io,
  nsl_icesugar, nsl_indication, nsl_color, nsl_sipeed, nsl_digilent,
  nsl_uart, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;
use nsl_video.terminal.all;
use nsl_color.rgb.all;

-- A link taken in, written over, and sent out again, with a second
-- screen of its own alongside.
--
-- What comes in on J4 goes out on J5 unchanged in shape: the same
-- mode, the same timing, the very same syncs.  A transmitter here is
-- told when to blank rather than working it out, so the raster it
-- sends is the raster that arrived.  Nothing is stored and nothing
-- drifts -- there is no frame to buffer and no rate to reconcile,
-- because both ends run off the clock the link brought with it.
--
-- That is what makes writing over it cheap.  A text overlay is drawn
-- at the mode's own size and pulled a pixel at a time in step with the
-- raster going by, and where the overlay has nothing to say the pixel
-- underneath goes through.  A pixel late would shift the picture, so
-- the raster is held a cycle to leave the overlay somewhere to be
-- asked from.
--
-- The panel on J6 is a screen of its own, not a window onto this one:
-- its own text, its own size, its own clock.  What it shows is what
-- used to go out of the UART.
entity boundary is
  port (
    clk_i : in std_ulogic;

    s_i : in std_ulogic_vector(1 to 2);

    uart_rx_i: in std_ulogic;
    uart_tx_o: out std_ulogic;

    ready_led_o: out std_ulogic;
    done_led_o: out std_ulogic;

    dvi_hpd_o: out std_ulogic;
    dvi_ddc_scl_io: inout std_logic;
    dvi_ddc_sda_io: inout std_logic;

    dvi_ck_i: in std_ulogic;
    dvi_d_i: in std_ulogic_vector(0 to 2);

    j5_io: inout nsl_digilent.pmod.pmod_double_t;
    j6_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;

  -- What the sink asks for, which settles what the screen on the far
  -- side is asked to show: the two are the same picture and the same
  -- timing, so a mode has to suit both ends.  A 5:4 panel takes 4:3
  -- and 5:4 modes and refuses 16:9 ones, and 65 MHz is well inside
  -- what this part receives and sends, so the choice is made here
  -- rather than by scaling afterwards.
  constant modes_c : nsl_video.mode.mode_vector(0 to 0)
    := (0 => nsl_video.mode.mode_std_640x480p60_c);
  constant screen_geometry_c : nsl_video.mode.geometry_t
    := nsl_video.mode.geometry(modes_c(0));
  constant panel_geometry_c : nsl_video.mode.geometry_t
    := nsl_video.mode.geometry(160, 80);

  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);

  constant hpd_period_l2_c : natural := 27;

  constant palette_c : rgb24_vector(0 to 7) := (
    rgb24_black,
    rgb24_red,
    rgb24_lime,
    rgb24_blue,
    rgb24_yellow,
    rgb24_cyan,
    rgb24_magenta,
    rgb24_white);

  -- What goes over the picture: two lines near the top left, drawn
  -- four times the size of the font so they are legible across a room.
  constant overlay_columns_c : natural := 20;
  constant overlay_labels_c : label_vector := (
    0 => text_label(row => 0, column => 0, length => overlay_columns_c,
                    foreground => 7, background => 0),
    1 => text_label(row => 1, column => 0, length => overlay_columns_c,
                    foreground => 2, background => 0));
  signal overlay_text_s : string(1 to 2 * overlay_columns_c);
  signal overlay_color_s : label_color_vector(0 to 7);

  -- What goes on the panel: what the UART used to say
  constant panel_columns_c : natural := 26;
  constant panel_rows_c : natural := 5;
  constant panel_labels_c : label_vector := (
    0 => text_label(0, 0, panel_columns_c, 7, 0),
    1 => text_label(1, 0, panel_columns_c, 5, 0),
    2 => text_label(2, 0, panel_columns_c, 5, 0),
    3 => text_label(3, 0, panel_columns_c, 2, 0),
    4 => text_label(4, 0, panel_columns_c, 4, 0));
  signal panel_text_s : string(1 to panel_rows_c * panel_columns_c);
  signal panel_color_s : label_color_vector(0 to 7);

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;

  signal ddc_i_s : nsl_i2c.i2c.i2c_i;
  signal ddc_o_s : nsl_i2c.i2c.i2c_o;
  signal selected_s : std_ulogic;

  signal hpd_s : std_ulogic;
  signal hpd_cycle_s : unsigned(hpd_period_l2_c-1 downto 0);
  signal addressed_s : std_ulogic;

  signal pixel_clock_s, serial_clock_s : std_ulogic;
  signal rx_locked_s : std_ulogic;
  signal rx_aligned_s, rx_control_s : std_ulogic_vector(0 to 2);
  signal tmds_in_s, tmds_out_s : nsl_dvi.dvi.symbol_vector_t;

  signal pixel_reset_n_s : std_ulogic;
  signal period_s : nsl_dvi.dvi.period_t;
  signal channels_s : byte_string(0 to 2);
  signal hsync_s, vsync_s, de_s : std_ulogic;
  signal timings_s : nsl_video.mode.timings_t;
  signal timings_valid_s : std_ulogic;

  -- The raster, held a cycle so the overlay has somewhere to be asked
  -- from before the pixel it belongs to goes out
  signal period_d_s : nsl_dvi.dvi.period_t;
  signal channels_d_s : byte_string(0 to 2);
  signal hsync_d_s, vsync_d_s, de_d_s : std_ulogic;

  signal de_prev_s, vsync_prev_s, frame_pending_s : std_ulogic;
  signal sof_s, sol_s : std_ulogic;

  signal overlay_s : nsl_video.pixel_stream.bus_t;
  signal overlay_pixel_s : nsl_video.pixel_stream.pixel_t;
  signal overlay_valid_s, overlay_synced_s : std_ulogic;
  signal overlay_lit_s : std_ulogic;
  -- What goes out is a DVI link, whatever came in.  A source speaking
  -- HDMI announces its periods and puts packets between its lines, and
  -- passing those on would mean passing on islands whose contents were
  -- never read -- announced, guarded, and holding nothing.  A screen
  -- taking DVI wants pixels or blanking and nothing else.
  signal tx_period_s : nsl_dvi.dvi.period_t;
  signal blended_s : byte_string(0 to 2);

  signal panel_s : nsl_video.pixel_stream.bus_t;
  signal panel_synced_s : std_ulogic;

  -- The same things the panel says, for when the panel is the thing
  -- in question
  constant line_length_c : natural := 57;
  constant uart_divisor_c : natural := clk_hz_c / 115200 - 1;
  signal line_s : byte_string(0 to line_length_c-1);
  signal tx_index_s : natural range 0 to line_length_c;
  signal tx_gap_s : unsigned(24 downto 0);
  signal tx_valid_s, tx_ready_s : std_ulogic;

  -- Preambles seen, which says whether the lanes are read properly
  signal vidpre_run_s, vidpre_hold_s, held_vidpre_s : unsigned(15 downto 0);
  signal probe_window_s : unsigned(19 downto 0);
  signal held_h_s, held_v_s : unsigned(15 downto 0);

  -- A stream states its components the way the colourspace names them,
  -- a link the way it sends them, which is blue first.
  function to_channels(p: nsl_video.pixel_stream.pixel_t) return byte_string
  is
    variable ret: byte_string(0 to 2);
  begin
    ret(0) := std_ulogic_vector(p(2)(7 downto 0));
    ret(1) := std_ulogic_vector(p(1)(7 downto 0));
    ret(2) := std_ulogic_vector(p(0)(7 downto 0));
    return ret;
  end function;

  function hex(v: unsigned; digits: natural) return string
  is
    alias a: unsigned(v'length-1 downto 0) is v;
    variable ret: string(1 to digits);
    variable n: natural;
  begin
    for i in 1 to digits
    loop
      n := to_integer(a(4*(digits-i)+3 downto 4*(digits-i)));
      if n < 10 then
        ret(i) := character'val(character'pos('0') + n);
      else
        ret(i) := character'val(character'pos('a') + n - 10);
      end if;
    end loop;
    return ret;
  end function;

  -- A row padded to the width its label states, so what goes in a row
  -- can be written as what it says rather than counted out by hand.
  function fit(t: string; width: natural) return string
  is
    alias a: string(1 to t'length) is t;
    variable ret: string(1 to width) := (others => ' ');
  begin
    for i in 1 to width
    loop
      exit when i > a'length;
      ret(i) := a(i);
    end loop;
    return ret;
  end function;

  function yes(v: std_ulogic) return string
  is
  begin
    if v = '1' then
      return "Y";
    end if;
    return "n";
  end function;

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_clocking.reset.reset_at_startup
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

  edid: nsl_dvi.ddc.ddc_edid_slave
    generic map(
      modes_c => modes_c,
      manufacturer_c => "NSL",
      product_code_c => 4,
      name_c => "NSL Overlay",
      h_size_mm_c => 304,
      v_size_mm_c => 228,
      hdmi_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      i2c_i => ddc_i_s,
      i2c_o => ddc_o_s,

      selected_o => selected_s
      );

  ddc_pads: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.scl => dvi_ddc_scl_io,
      bus_io.sda => dvi_ddc_sda_io,
      bus_o => ddc_i_s,
      bus_i => ddc_o_s
      );

  hpd_gen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      hpd_cycle_s <= hpd_cycle_s + 1;

      if addressed_s = '1' then
        hpd_s <= '1';
      elsif hpd_cycle_s(hpd_cycle_s'left downto hpd_cycle_s'left-1) = "00" then
        hpd_s <= '0';
      else
        hpd_s <= '1';
      end if;

      if selected_s = '1' then
        addressed_s <= '1';
      end if;
    end if;

    if reset_n_s = '0' then
      hpd_cycle_s <= (others => '0');
      hpd_s <= '0';
      addressed_s <= '0';
    end if;
  end process;

  receiver: nsl_dvi.transceiver.dvi_receiver
    generic map(
      mode_c => modes_c(0)
      )
    port map(
      reset_n_i => reset_n_s,

      clock_i => dvi_ck_i,
      data_i => dvi_d_i,

      realign_i => s_i(1),

      pixel_clock_o => pixel_clock_s,
      serial_clock_o => serial_clock_s,
      locked_o => rx_locked_s,

      aligned_o => rx_aligned_s,
      control_o => rx_control_s,

      tmds_o => tmds_in_s
      );

  pixel_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => pixel_clock_s,
      data_i => rx_locked_s,
      data_o => pixel_reset_n_s
      );

  decoder: nsl_dvi.decoder.sink_stream_decoder
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,

      tmds_i => tmds_in_s,

      period_o => period_s,
      pixel_o => channels_s,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => open,
      di_data_o => open
      );

  de_s <= '1' when period_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA else '0';
  de_d_s <= '1' when period_d_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA else '0';

  measurer: nsl_video.raster.raster_measurer
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      de_i => de_s,
      hsync_i => hsync_s,
      vsync_i => vsync_s,

      timings_o => timings_s,
      valid_o => timings_valid_s
      );

  -- The raster held a cycle, and where a line and a frame open said
  -- before the pixel that opens them is asked for
  raster_delay: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      period_d_s <= period_s;
      channels_d_s <= channels_s;
      hsync_d_s <= hsync_s;
      vsync_d_s <= vsync_s;

      de_prev_s <= de_s;
      vsync_prev_s <= vsync_s;

      if vsync_s = '1' and vsync_prev_s = '0' then
        frame_pending_s <= '1';
      elsif sof_s = '1' then
        frame_pending_s <= '0';
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      period_d_s <= nsl_dvi.dvi.PERIOD_CONTROL;
      de_prev_s <= '0';
      vsync_prev_s <= '0';
      frame_pending_s <= '0';
    end if;
  end process;

  sol_s <= '1' when de_s = '1' and de_prev_s = '0' else '0';
  sof_s <= sol_s and frame_pending_s;

  overlay: nsl_video.terminal.terminal_labels
    generic map(
      row_count_l2_c => 5,
      column_count_l2_c => 6,
      character_count_l2_c => 8,
      color_palette_c => palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => overlay_labels_c,
      font_hscale_c => 2,
      font_vscale_c => 2,
      config_c => pixel_config_c,
      geometry_c => screen_geometry_c
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      out_o => overlay_s.m,
      out_i => overlay_s.s,

      text_i => overlay_text_s,
      color_i => overlay_color_s
      );

  -- Pulled a pixel at a time in step with the raster going by.  A
  -- raster off a wire cannot be told to wait, so neither can this.
  overlay_unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => pixel_config_c,
      raster_can_wait_c => false
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      in_i => overlay_s.m,
      in_o => overlay_s.s,

      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => de_d_s,
      valid_o => overlay_valid_s,
      pixel_o => overlay_pixel_s,

      synced_o => overlay_synced_s
      );

  -- Where the overlay has nothing to say, the picture goes through.
  -- Black is what it says nothing with.
  overlay_lit_s <= '1' when overlay_valid_s = '1'
                   and not (overlay_pixel_s(0) = 0
                            and overlay_pixel_s(1) = 0
                            and overlay_pixel_s(2) = 0)
                   else '0';

  blended_s <= to_channels(overlay_pixel_s) when overlay_lit_s = '1'
               else channels_d_s;

  tx_period_s <= nsl_dvi.dvi.PERIOD_VIDEO_DATA
                 when period_d_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA
                 else nsl_dvi.dvi.PERIOD_CONTROL;

  encoder: nsl_dvi.encoder.source_stream_encoder
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,

      period_i => tx_period_s,
      pixel_i => blended_s,
      hsync_i => hsync_d_s,
      vsync_i => vsync_d_s,

      tmds_o => tmds_out_s
      );

  driver: nsl_sipeed.pmod_dvi.pmod_dvi_output
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,
      serial_clock_i => serial_clock_s,

      tmds_i => tmds_out_s,

      pmod_o => j5_io
      );

  -- A screen of its own, on the board's clock
  panel_text: nsl_video.terminal.terminal_labels
    generic map(
      row_count_l2_c => 4,
      column_count_l2_c => 5,
      character_count_l2_c => 8,
      color_palette_c => palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => panel_labels_c,
      config_c => pixel_config_c,
      geometry_c => panel_geometry_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      out_o => panel_s.m,
      out_i => panel_s.s,

      text_i => panel_text_s,
      color_i => panel_color_s
      );

  display: nsl_icesugar.pmod_lcd_096.pmod_lcd_096_driver
    generic map(
      clock_i_hz_c => clk_hz_c,
      config_c => pixel_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      pixel_i => panel_s.m,
      pixel_o => panel_s.s,

      synced_o => panel_synced_s,

      pmod_io => j6_io
      );

  -- A label states its foreground and background as places in this
  -- port, and this port states the palette entries they stand for.
  -- Standing for themselves is the plainest thing they can do; tying
  -- them all to nothing paints every label in the first colour, which
  -- here is black on black.
  colors: for i in 0 to 7
  generate
    overlay_color_s(i) <= to_unsigned(i, overlay_color_s(i)'length);
    panel_color_s(i) <= to_unsigned(i, panel_color_s(i)'length);
  end generate;

  overlay_text_s <= fit("NSL CAPTURE", overlay_columns_c)
                    & fit("IN " & hex(timings_s.h.active, 4) & "x"
                          & hex(timings_s.v.active, 4) & " "
                          & yes(timings_valid_s), overlay_columns_c);

  panel_text_s <= fit("NSL DVI OVERLAY", panel_columns_c)
                  & fit("H " & hex(timings_s.h.active, 4)
                        & " " & hex(timings_s.h.blank, 4)
                        & " " & hex(timings_s.h.width, 4), panel_columns_c)
                  & fit("V " & hex(timings_s.v.active, 4)
                        & " " & hex(timings_s.v.blank, 4)
                        & " " & hex(timings_s.v.width, 4), panel_columns_c)
                  & fit("LOCK " & yes(rx_locked_s)
                        & " ALIGN " & yes(rx_aligned_s(0))
                        & yes(rx_aligned_s(1)) & yes(rx_aligned_s(2)),
                        panel_columns_c)
                  & fit("LANES " & yes(rx_control_s(0))
                        & yes(rx_control_s(1)) & yes(rx_control_s(2))
                        & " OVL " & yes(overlay_synced_s), panel_columns_c);

  preambles: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      probe_window_s <= probe_window_s + 1;

      if probe_window_s = 0 then
        vidpre_hold_s <= vidpre_run_s;
        vidpre_run_s <= (others => '0');
      elsif period_s = nsl_dvi.dvi.PERIOD_VIDEO_PRE then
        vidpre_run_s <= vidpre_run_s + 1;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      probe_window_s <= (others => '0');
      vidpre_run_s <= (others => '0');
      vidpre_hold_s <= (others => '0');
    end if;
  end process;

  line_s <= to_byte_string("H ") & to_byte_string(hex(held_h_s, 4))
            & to_byte_string(" V ") & to_byte_string(hex(held_v_s, 4))
            & to_byte_string(" T ") & to_byte_string(yes(timings_valid_s))
            & to_byte_string(" L ") & to_byte_string(yes(rx_locked_s))
            & to_byte_string(" A ") & to_byte_string(yes(rx_aligned_s(0)))
            & to_byte_string(yes(rx_aligned_s(1)))
            & to_byte_string(yes(rx_aligned_s(2)))
            & to_byte_string(" C ") & to_byte_string(yes(rx_control_s(0)))
            & to_byte_string(yes(rx_control_s(1)))
            & to_byte_string(yes(rx_control_s(2)))
            & to_byte_string(" P ") & to_byte_string(hex(held_vidpre_s, 4))
            & to_byte_string(" O ") & to_byte_string(yes(overlay_synced_s))
            & to_byte_string(" S ") & to_byte_string(yes(panel_synced_s))
            & to_byte_string(" HPD ") & to_byte_string(yes(hpd_s))
            & to_byte_string(yes(addressed_s))
            & to_byte_string("" & cr & lf);

  report_gen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if tx_index_s = line_length_c then
        tx_gap_s <= tx_gap_s + 1;
        if tx_gap_s(tx_gap_s'left) = '1' then
          tx_gap_s <= (others => '0');
          tx_index_s <= 0;
          held_vidpre_s <= vidpre_hold_s;
          held_h_s <= timings_s.h.active;
          held_v_s <= timings_s.v.active;
        end if;
      elsif tx_ready_s = '1' then
        tx_index_s <= tx_index_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      tx_index_s <= line_length_c;
      tx_gap_s <= (others => '0');
    end if;
  end process;

  tx_valid_s <= '1' when tx_index_s /= line_length_c else '0';

  uart: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => nsl_uart.serdes.PARITY_NONE
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      divisor_i => to_unsigned(uart_divisor_c, 16),
      uart_o => uart_tx_o,
      data_i => std_ulogic_vector(line_s(tx_index_s mod line_length_c)),
      ready_o => tx_ready_s,
      valid_i => tx_valid_s
      );

  dvi_hpd_o <= hpd_s;
  ready_led_o <= hpd_s;
  -- One bit about the link, this design having no other
  done_led_o <= rx_locked_s;

end arch;
