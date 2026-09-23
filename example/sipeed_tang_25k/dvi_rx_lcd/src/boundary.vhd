library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_dvi, nsl_i2c, nsl_video, nsl_amba,
  nsl_icesugar, nsl_sipeed, nsl_digilent, nsl_uart, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
-- For the equality on a symbol period
use nsl_dvi.dvi.all;

-- A thumbnail of whatever a source is showing, on a 160x80 panel.
--
-- The sink half is the one already built: hot plug detect, an EDID
-- stating one mode, and a receiver following the link it brings.  What
-- follows it is the point here -- a raster off the wire turned into a
-- stream, made small enough for the panel, carried across to the
-- board's clock and handed to a display driver that knows nothing
-- about where it came from.
--
-- Nothing between the decoder and the panel is about HDMI.  Making the
-- picture smaller is one AXI4-Stream block, crossing to another clock
-- is another, and the panel driver takes the same stream a test
-- pattern generator would hand it.
--
-- The picture is thinned rather than filtered: one pixel in eight
-- across and one line in nine down, which at 1280x720 is exactly
-- 160x80.  A thumbnail of a screen full of text is therefore a mess of
-- aliasing, and legibly so -- what it shows is that pixels are
-- arriving, in the right order, the right way up.
--
-- The geometry the thinning works to is the mode the EDID states.  A
-- source insisting on something else would still light the panel, with
-- the picture sheared: nothing here measures what actually arrived and
-- adjusts, because the point is the path rather than the plumbing.
--
-- Two LEDs: ready is hot plug detect, done is a source having read the
-- EDID.
entity boundary is
  port (
    clk_i : in std_ulogic;

    -- s_i(1) makes every lane look for its symbol boundary again.  Hot
    -- plug detect is not touched, so the source is told nothing and
    -- has no reason to start over.
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

  constant modes_c : nsl_video.mode.mode_vector(0 to 0)
    := (0 => nsl_video.mode.mode_std_1280x720p60_c);

  constant source_geometry_c : nsl_video.mode.geometry_t
    := nsl_video.mode.geometry(modes_c(0));
  constant panel_geometry_c : nsl_video.mode.geometry_t
    := nsl_video.mode.geometry(160, 80);

  -- A raster off a wire cannot be told to wait, so what it turns into
  -- carries no ready.  Everything past the thinning can be told to
  -- wait, and is.
  constant capture_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1, ready => false);
  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);

  -- The thinning hands over a line of the panel in one burst -- 160
  -- beats in the 1280 link cycles of one source line, which is
  -- seventeen microseconds -- and the panel takes about a hundred and
  -- seventy microseconds over the same 160.  The eight source lines
  -- skipped after each one give it time to catch up, but not all of
  -- it: some forty beats a group stay behind, and over the eighty
  -- lines of a frame that is three thousand odd.
  --
  -- So a frame's backlog has to fit, or beats are dropped from the
  -- middle of frames and the far end never holds a frame long enough
  -- to show it.
  constant fifo_depth_c : natural := 4096;

  -- Long enough that a source has time to notice
  constant hpd_period_l2_c : natural := 27;

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;

  signal ddc_i_s : nsl_i2c.i2c.i2c_i;
  signal ddc_o_s : nsl_i2c.i2c.i2c_o;
  signal selected_s : std_ulogic;

  signal hpd_s : std_ulogic;
  signal hpd_cycle_s : unsigned(hpd_period_l2_c-1 downto 0);
  signal addressed_s : std_ulogic;

  signal pixel_clock_s : std_ulogic;
  signal rx_locked_s : std_ulogic;
  signal rx_aligned_s, rx_control_s : std_ulogic_vector(0 to 2);
  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  signal pixel_reset_n_s : std_ulogic;
  signal period_s : nsl_dvi.dvi.period_t;
  signal de_s, hsync_s, vsync_s : std_ulogic;
  signal channels_s : byte_string(0 to 2);
  signal timings_s : nsl_video.mode.timings_t;
  signal timings_valid_s : std_ulogic;

  -- Off the wire, thinned, across, and out
  signal captured_s, small_s, panel_s : nsl_video.pixel_stream.bus_t;
  signal overflow_s, synced_s : std_ulogic;

  signal fifo_clock_s : std_ulogic_vector(0 to 1);

  -- Where the picture got to.  Each of the last four blinks rather
  -- than lights, since what is asked is whether beats keep coming
  -- rather than whether one ever did.
  signal led_s : std_ulogic_vector(1 to 8);
  signal osc_s : std_ulogic;
  signal osc_beat_s : unsigned(24 downto 0);
  -- Counted at rates that differ by a factor of seventy two, so the
  -- bit watched differs too: a light has to blink slowly enough to be
  -- seen blinking.
  signal captured_beat_s : unsigned(25 downto 0);
  signal small_beat_s, panel_beat_s : unsigned(19 downto 0);
  signal overflow_seen_s : std_ulogic;

  -- Beats taken rather than beats offered, which is the difference
  -- between a stage running and a stage stuck holding one out
  constant window_l2_c : natural := 20;
  signal pixel_window_s : unsigned(window_l2_c-1 downto 0);
  signal cap_run_s, cap_hold_s : unsigned(31 downto 0);
  -- Lines and frames the capturer closed, which is what the thinning
  -- counts by.  Beats alone say nothing about framing.
  signal last_run_s, last_hold_s : unsigned(15 downto 0);
  signal sof_run_s, sof_hold_s : unsigned(15 downto 0);
  signal offer_run_s, offer_hold_s : unsigned(31 downto 0);
  signal dec_run_s, dec_hold_s : unsigned(31 downto 0);

  signal board_window_s : unsigned(window_l2_c-1 downto 0);
  signal pan_run_s, pan_hold_s : unsigned(31 downto 0);
  signal fifo_available_s : integer range 0 to fifo_depth_c + 1;
  signal fifo_free_s : integer range 0 to fifo_depth_c;
  -- The two halves of the handshake into the panel, which say which of
  -- the two is the one not moving
  signal out_valid_s, out_ready_s : std_ulogic;
  signal held_free_s : unsigned(15 downto 0);
  signal held_valid_s, held_ready_s : std_ulogic;

  -- A panel scan opens a frame once, early, and then stands at its
  -- first pixel until one arrives.  A link takes seconds to come up,
  -- so a scan started at power-up opens its frame while there is still
  -- nothing to put in it, and the two end up waiting on each other.
  -- Holding the panel until there are pixels to give it settles the
  -- order once and for all.

  -- A frame at a time to the panel, or none.
  signal gated_s : nsl_video.pixel_stream.bus_t;
  signal frame_keep_s, frame_turn_s, passing_s : std_ulogic;
  -- Every lane reading properly.  A link coming up spends a second or
  -- so finding where to cut its symbols, and what it decodes meanwhile
  -- is not a picture.  These come off the receiver on the link's own
  -- clock, which is this one.
  signal lanes_good_s : std_ulogic;

  constant line_length_c : natural := 104;
  constant uart_divisor_c : natural := clk_hz_c / 115200 - 1;

  signal line_s : byte_string(0 to line_length_c-1);
  signal tx_index_s : natural range 0 to line_length_c;
  signal tx_gap_s : unsigned(24 downto 0);
  signal tx_valid_s, tx_ready_s : std_ulogic;

  signal held_h_s, held_v_s : unsigned(15 downto 0);
  signal held_cap_s, held_dec_s, held_pan_s : unsigned(31 downto 0);
  signal held_avail_s : unsigned(15 downto 0);
  signal held_last_s, held_sof_s : unsigned(15 downto 0);
  signal held_offer_s : unsigned(31 downto 0);
  -- Beats dropped, counted rather than remembered: a flag set once at
  -- startup and a stream losing beats every line look the same from a
  -- flag, and only one of them is a problem.
  signal drop_run_s, drop_hold_s, held_drop_s : unsigned(15 downto 0);
  -- Preambles seen, which says whether the lanes carrying green and
  -- red are being read properly.  A link sends one of each a line.
  signal vidpre_run_s, vidpre_hold_s, held_vidpre_s : unsigned(15 downto 0);
  signal dipre_run_s, dipre_hold_s, held_dipre_s : unsigned(15 downto 0);

  function hex4(v: unsigned) return byte_string
  is
    alias a: unsigned(15 downto 0) is v;
    variable ret: byte_string(0 to 3);
    variable n: unsigned(3 downto 0);
  begin
    for i in 0 to 3
    loop
      n := a(15 - i*4 downto 12 - i*4);
      if n < 10 then
        ret(i) := to_byte(character'pos('0') + to_integer(n));
      else
        ret(i) := to_byte(character'pos('a') + to_integer(n) - 10);
      end if;
    end loop;
    return ret;
  end function;

  function bit_char(v: std_ulogic) return byte_string
  is
  begin
    if v = '1' then
      return to_byte_string("1");
    end if;
    return to_byte_string("0");
  end function;

  -- A decoder states its channels in the order the link sends them,
  -- which is blue first.  A stream states them in the order the
  -- colorspace names them.
  function to_pixel(channels: byte_string) return nsl_video.pixel_stream.pixel_t
  is
    variable ret: nsl_video.pixel_stream.pixel_t
      := nsl_video.pixel_stream.pixel_zero_c;
  begin
    ret(0) := resize(unsigned(channels(2)), ret(0)'length);
    ret(1) := resize(unsigned(channels(1)), ret(1)'length);
    ret(2) := resize(unsigned(channels(0)), ret(2)'length);
    return ret;
  end function;

begin

  osc: nsl_clocking.oscillator.clock_internal
    port map(
      clock_o => osc_s
      );

  osc_beat: process(osc_s) is
  begin
    if rising_edge(osc_s) then
      osc_beat_s <= osc_beat_s + 1;
    end if;
  end process;

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
      product_code_c => 2,
      name_c => "NSL Thumbnail",
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

  -- Appearing and disappearing until somebody reads us, then staying
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
      locked_o => rx_locked_s,

      aligned_o => rx_aligned_s,
      control_o => rx_control_s,

      tmds_o => tmds_s
      );

  -- Everything below the link runs on the link's own clock, and only
  -- once there is one.
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

      tmds_i => tmds_s,

      period_o => period_s,
      pixel_o => channels_s,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => open,
      di_data_o => open
      );

  de_s <= '1' when period_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA else '0';

  -- What a frame's shape is, which is what says where one ends
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

  capture: nsl_video.raster.pixel_stream_capturer
    generic map(
      config_c => capture_config_c
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      de_i => de_s,
      vsync_i => vsync_s,
      pixel_i => to_pixel(channels_s),

      timings_i => timings_s,
      timings_valid_i => timings_valid_s,

      out_o => captured_s.m,
      out_i => captured_s.s
      );

  thumbnail: nsl_video.raster.pixel_stream_decimator
    generic map(
      in_config_c => capture_config_c,
      out_config_c => pixel_config_c,
      in_geometry_c => source_geometry_c,
      out_geometry_c => panel_geometry_c
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      in_i => captured_s.m,
      in_o => captured_s.s,

      out_o => small_s.m,
      out_i => small_s.s,

      overflow_o => overflow_s
      );

  -- The panel takes about seven hundred and seventy thousand pixels a
  -- second, and a hundred and sixty by eighty at sixty frames is seven
  -- hundred and sixty eight thousand.  That is no margin at all, so
  -- half the frames go and the rest arrive whole.
  --
  -- Whole is the point.  Dropping pixels to make a stream fit leaves
  -- every frame short and the far end never finds one it can follow;
  -- dropping frames leaves the ones that get through exactly as they
  -- were.
  lanes_good_s <= rx_control_s(0) and rx_control_s(1) and rx_control_s(2);

  -- A frame is let through only if every lane was reading properly
  -- when it opened.  Showing the search happen is worse than showing
  -- nothing: a panel holding its last picture for a second beats one
  -- painting noise.
  passing_s <= (frame_turn_s and lanes_good_s)
               when nsl_video.pixel_stream.is_sof(pixel_config_c, small_s.m)
               else frame_keep_s;

  gated_s.m <= small_s.m when passing_s = '1'
               else nsl_video.pixel_stream.transfer_defaults(pixel_config_c);
  small_s.s <= gated_s.s when passing_s = '1'
               else nsl_video.pixel_stream.accept(pixel_config_c, true);

  frame_gate: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      if nsl_video.pixel_stream.is_taken(pixel_config_c, small_s.m, small_s.s) then
        if nsl_video.pixel_stream.is_sof(pixel_config_c, small_s.m) then
          frame_keep_s <= frame_turn_s;
        end if;

        if nsl_video.pixel_stream.is_last(pixel_config_c, small_s.m)
          and nsl_video.pixel_stream.is_eof(pixel_config_c, small_s.m) then
          frame_turn_s <= not frame_turn_s;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      frame_keep_s <= '0';
      frame_turn_s <= '1';
    end if;
  end process;

  fifo_clock_s(0) <= pixel_clock_s;
  fifo_clock_s(1) <= clock_s;

  -- The link's clock on one side and the board's on the other.  It is
  -- a plain stream FIFO: nothing in it knows what the beats hold.
  cross: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => nsl_video.pixel_stream.as_stream_config(pixel_config_c),
      depth_c => fifo_depth_c,
      clock_count_c => 2
      )
    port map(
      clock_i => fifo_clock_s,
      reset_n_i => pixel_reset_n_s,

      in_i => gated_s.m,
      in_o => gated_s.s,
      in_free_o => fifo_free_s,

      out_o => panel_s.m,
      out_i => panel_s.s,
      out_available_o => fifo_available_s
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

      synced_o => synced_s,

      pmod_io => j6_io
      );

  -- Beats counted where they pass, so a light going on and staying on
  -- is a stage that ran once and stopped, and a light blinking is one
  -- still running.
  pixel_beats: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      if nsl_video.pixel_stream.is_valid(capture_config_c, captured_s.m) then
        captured_beat_s <= captured_beat_s + 1;
      end if;
      if nsl_video.pixel_stream.is_valid(pixel_config_c, small_s.m) then
        small_beat_s <= small_beat_s + 1;
      end if;
      if overflow_s = '1' then
        overflow_seen_s <= '1';
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      captured_beat_s <= (others => '0');
      small_beat_s <= (others => '0');
      overflow_seen_s <= '0';
    end if;
  end process;

  panel_beats: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if nsl_video.pixel_stream.is_taken(pixel_config_c, panel_s.m, panel_s.s) then
        panel_beat_s <= panel_beat_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      panel_beat_s <= (others => '0');
    end if;
  end process;

  counters: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      pixel_window_s <= pixel_window_s + 1;

      if pixel_window_s = 0 then
        cap_hold_s <= cap_run_s;
        dec_hold_s <= dec_run_s;
        drop_hold_s <= drop_run_s;
        vidpre_hold_s <= vidpre_run_s;
        dipre_hold_s <= dipre_run_s;
        drop_run_s <= (others => '0');
        vidpre_run_s <= (others => '0');
        dipre_run_s <= (others => '0');
        last_hold_s <= last_run_s;
        sof_hold_s <= sof_run_s;
        offer_hold_s <= offer_run_s;
        cap_run_s <= (others => '0');
        dec_run_s <= (others => '0');
        last_run_s <= (others => '0');
        sof_run_s <= (others => '0');
        offer_run_s <= (others => '0');
      else
        if nsl_video.pixel_stream.is_taken(capture_config_c,
                                           captured_s.m, captured_s.s) then
          cap_run_s <= cap_run_s + 1;

          if nsl_video.pixel_stream.is_last(capture_config_c, captured_s.m) then
            last_run_s <= last_run_s + 1;
          end if;
          if nsl_video.pixel_stream.is_sof(capture_config_c, captured_s.m) then
            sof_run_s <= sof_run_s + 1;
          end if;
        end if;

        if nsl_video.pixel_stream.is_valid(pixel_config_c, small_s.m) then
          offer_run_s <= offer_run_s + 1;
        end if;
        if overflow_s = '1' then
          drop_run_s <= drop_run_s + 1;
        end if;
        if period_s = nsl_dvi.dvi.PERIOD_VIDEO_PRE then
          vidpre_run_s <= vidpre_run_s + 1;
        end if;
        if period_s = nsl_dvi.dvi.PERIOD_DI_PRE then
          dipre_run_s <= dipre_run_s + 1;
        end if;
        if nsl_video.pixel_stream.is_taken(pixel_config_c,
                                           small_s.m, small_s.s) then
          dec_run_s <= dec_run_s + 1;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      pixel_window_s <= (others => '0');
      cap_run_s <= (others => '0');
      dec_run_s <= (others => '0');
      cap_hold_s <= (others => '0');
      dec_hold_s <= (others => '0');
      last_run_s <= (others => '0');
      sof_run_s <= (others => '0');
      offer_run_s <= (others => '0');
      last_hold_s <= (others => '0');
      sof_hold_s <= (others => '0');
      offer_hold_s <= (others => '0');
      drop_run_s <= (others => '0');
      drop_hold_s <= (others => '0');
      vidpre_run_s <= (others => '0');
      vidpre_hold_s <= (others => '0');
      dipre_run_s <= (others => '0');
      dipre_hold_s <= (others => '0');
    end if;
  end process;

  board_counters: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      board_window_s <= board_window_s + 1;

      if board_window_s = 0 then
        pan_hold_s <= pan_run_s;
        pan_run_s <= (others => '0');
      elsif nsl_video.pixel_stream.is_taken(pixel_config_c,
                                            panel_s.m, panel_s.s) then
        pan_run_s <= pan_run_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      board_window_s <= (others => '0');
      pan_run_s <= (others => '0');
      pan_hold_s <= (others => '0');
    end if;
  end process;

  out_valid_s <= '1' when nsl_video.pixel_stream.is_valid(pixel_config_c, panel_s.m)
                 else '0';
  out_ready_s <= '1' when nsl_video.pixel_stream.is_ready(pixel_config_c, panel_s.s)
                 else '0';

  line_s <= to_byte_string("T ") & hex4(timings_s.h.active)
            & to_byte_string(" ") & hex4(timings_s.v.active)
            & bit_char(timings_valid_s)
            & to_byte_string(" C ") & hex4(held_cap_s(31 downto 16))
            & hex4(held_cap_s(15 downto 0))
            & to_byte_string(" D ") & hex4(held_dec_s(31 downto 16))
            & hex4(held_dec_s(15 downto 0))
            & to_byte_string(" P ") & hex4(held_pan_s(31 downto 16))
            & hex4(held_pan_s(15 downto 0))
            & to_byte_string(" L ") & hex4(held_last_s)
            & to_byte_string(" ") & hex4(held_sof_s)
            & to_byte_string(" O ") & hex4(held_offer_s(31 downto 16))
            & hex4(held_offer_s(15 downto 0))
            & to_byte_string(" W ") & hex4(held_drop_s)
            & to_byte_string(" ") & hex4(held_vidpre_s)
            & to_byte_string(" ") & hex4(held_dipre_s)
            -- What the aligner thinks it achieved, per lane, and
            -- whether each lane is still seeing control symbols.  A
            -- lane it gave up on and a lane it settled wrongly on need
            -- different answers.
            & to_byte_string(" A ") & bit_char(rx_aligned_s(0))
            & bit_char(rx_aligned_s(1)) & bit_char(rx_aligned_s(2))
            & to_byte_string(" ") & bit_char(rx_control_s(0))
            & bit_char(rx_control_s(1)) & bit_char(rx_control_s(2))
            & to_byte_string(" S ") & bit_char(synced_s)
            & bit_char(overflow_seen_s)
            & bit_char(held_valid_s) & bit_char(held_ready_s)
            & to_byte_string("" & cr & lf);

  report_gen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if tx_index_s = line_length_c then
        tx_gap_s <= tx_gap_s + 1;
        if tx_gap_s(tx_gap_s'left) = '1' then
          tx_gap_s <= (others => '0');
          tx_index_s <= 0;
          held_cap_s <= cap_hold_s;
          held_dec_s <= dec_hold_s;
          held_pan_s <= pan_hold_s;
          held_avail_s <= to_unsigned(fifo_available_s, 16);
          held_free_s <= to_unsigned(fifo_free_s, 16);
          held_last_s <= last_hold_s;
          held_sof_s <= sof_hold_s;
          held_offer_s <= offer_hold_s;
          held_drop_s <= drop_hold_s;
          held_vidpre_s <= vidpre_hold_s;
          held_dipre_s <= dipre_hold_s;
          held_valid_s <= out_valid_s;
          held_ready_s <= out_ready_s;
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

  led_s(1) <= osc_beat_s(osc_beat_s'left);
  led_s(2) <= reset_n_s;
  led_s(3) <= rx_locked_s and rx_aligned_s(0) and rx_aligned_s(1)
              and rx_aligned_s(2);
  led_s(4) <= timings_valid_s;
  led_s(5) <= captured_beat_s(captured_beat_s'left);
  led_s(6) <= small_beat_s(small_beat_s'left);
  led_s(7) <= panel_beat_s(panel_beat_s'left);
  -- The panel driver's own view: whether it has found a frame in what
  -- it is being handed
  led_s(8) <= synced_s;

  leds: nsl_sipeed.pmod_8xled.pmod_8xled_driver
    port map(
      pmod_io => j5_io,
      led_i => led_s
      );

  dvi_hpd_o <= hpd_s;
  ready_led_o <= hpd_s;
  -- A frame was thrown away for want of room, which is the one failure
  -- that leaves everything else looking healthy
  done_led_o <= overflow_seen_s;

end arch;
