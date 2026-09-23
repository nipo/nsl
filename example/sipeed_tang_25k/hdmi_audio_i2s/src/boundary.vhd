library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_dvi, nsl_hdmi, nsl_i2c, nsl_video,
  nsl_icesugar, nsl_indication, nsl_color, nsl_digilent, nsl_audio,
  nsl_i2s, nsl_amba, nsl_uart, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;
use nsl_video.terminal.all;
use nsl_color.rgb.all;

-- The sound off an HDMI link, played out of a converter.
--
-- What arrives on J4 is a picture with audio packed into its blanking.
-- Nothing here shows the picture: the pixels are decoded only far
-- enough to find where the data islands are, and what comes out of
-- them is two channels of PCM which go to the DAC on J5.  J6 says what
-- the link is doing.
--
-- The whole of this is a rate problem.  A source sends samples when it
-- has them rather than evenly, and says how fast they were meant to
-- come out only through N and CTS, which mean
--
--   128 * fs = link clock * N / CTS
--
-- A converter has to be given that rate and not one near it: it is
-- fed samples at whatever rate they arrived and plays them at whatever
-- rate it is clocked, and a part per million between the two empties
-- or fills whatever sits in between, forever.  Nothing downstream can
-- fix that -- a buffer only says how long it takes to go wrong.
--
-- So the converter's clocks are not made here, they are counted out of
-- what the source said.  An accumulator takes N every link cycle and
-- gives a tick back every CTS it holds, and the master, bit and word
-- clocks are all divisions of those ticks.  That makes the word clock
-- exactly the rate the source stated, not approximately, and the
-- buffer between the two sits at whatever depth it first reached.
--
-- The cost is that a tick lands on a link cycle, so a clock made of
-- them has periods a whole number of link cycles long, coming out long
-- or short as the accumulator falls.  A converter wants its master
-- clock between 45 and 55% duty, which needs the link clock at six
-- times it or better -- 1280x720 at 74.25 MHz against a 12.288 MHz
-- master clock is six and a fraction, which is why the mode below is
-- that one and not something slower.
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

  -- 74.25 MHz, for the reason given above.  Nothing is drawn with it,
  -- but the link clock is what the audio rate is counted against, so
  -- the mode is an audio decision here rather than a picture one.
  constant modes_c : nsl_video.mode.mode_vector(0 to 0)
    := (0 => nsl_video.mode.mode_std_1280x720p60_c);

  -- Ticks per frame of audio.  The converter's master clock runs at
  -- 256 times the frame rate, which is the slowest it takes, and a
  -- clock needs a tick for each of its edges.
  constant mclk_ratio_c : natural := 512;
  -- Which leaves the 128 the standard states, and that is what the
  -- bit and word clocks are made from.
  constant i2s_tick_divisor_c : natural := mclk_ratio_c / 128;

  -- What the link hands over and what the converter is sent: two
  -- channels of twenty four bits.  No sideband -- V, U and C say
  -- nothing an I2S wire can carry, and are shown on the panel instead
  -- of being dragged through the buffer.
  constant audio_config_c : nsl_audio.pcm_stream.config_t
    := nsl_hdmi.audio_stream.stream_config(sideband => false);

  -- A slot is wider than a sample: the bit clock runs at 64 times the
  -- word clock because that divides the master clock by four, and the
  -- converter reads the leading twenty four bits of each half and
  -- ignores the rest.
  constant slot_bits_c : natural := 32;

  -- Samples arrive in bursts, inside blanking, and leave one at a
  -- time.  A vertical blanking's worth is about thirty frames, so this
  -- is far more than the burst needs -- what it really buys is the
  -- start, where the link is already sending and the converter has not
  -- yet been told a rate.
  constant fifo_depth_c : natural := 512;

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

  constant panel_columns_c : natural := 26;
  constant panel_rows_c : natural := 9;
  constant panel_labels_c : label_vector := (
    0 => text_label(0, 0, panel_columns_c, 7, 0),
    1 => text_label(1, 0, panel_columns_c, 5, 0),
    2 => text_label(2, 0, panel_columns_c, 5, 0),
    3 => text_label(3, 0, panel_columns_c, 4, 0),
    4 => text_label(4, 0, panel_columns_c, 4, 0),
    5 => text_label(5, 0, panel_columns_c, 2, 0),
    6 => text_label(6, 0, panel_columns_c, 6, 0),
    7 => text_label(7, 0, panel_columns_c, 6, 0),
    8 => text_label(8, 0, panel_columns_c, 6, 0));
  signal panel_text_s : string(1 to panel_rows_c * panel_columns_c);
  signal panel_color_s : label_color_vector(0 to 7);

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
  signal di_hdr_s : std_ulogic_vector(1 downto 0);
  signal di_data_s : std_ulogic_vector(7 downto 0);
  signal hsync_s, vsync_s, de_s : std_ulogic;
  signal timings_s : nsl_video.mode.timings_t;
  signal timings_valid_s : std_ulogic;

  signal packet_valid_s, packet_error_s : std_ulogic;
  signal packet_s : nsl_hdmi.hdmi.data_island_t;

  signal acr_valid_s, acr_ready_s : std_ulogic;
  signal acr_n_s, acr_cts_s : unsigned(19 downto 0);
  signal audio_valid_s, audio_block_s : std_ulogic;
  -- Samples are only worth keeping once there is something to play
  -- them at.  See the bring-up below.
  signal audio_taken_s : std_ulogic;
  signal audio_a_s, audio_b_s : nsl_hdmi.audio.channel_sample_t;

  -- The converter's three clocks, all counted off the one stream of
  -- ticks so that the ratio between them is exact whatever the link
  -- clock does.
  signal mclk_tick_s, i2s_tick_s : std_ulogic;
  signal tick_divider_s : natural range 0 to i2s_tick_divisor_c-1;
  signal mclk_s, sck_s, ws_s : std_ulogic;

  signal audio_s, played_s : nsl_amba.axi4_stream.bus_t;
  signal fifo_level_s : integer range 0 to fifo_depth_c + 1;
  signal overflow_s, underflow_s : std_ulogic;
  signal lost_s : unsigned(7 downto 0);

  -- Whether the word clock has been started.  See the bring-up below.
  signal playing_s : std_ulogic;
  -- What the buffer held when it was, which is what says the bring-up
  -- did what it meant to.
  signal start_level_s : unsigned(11 downto 0);
  -- How long the buffer has been on the floor, and how many times it
  -- has had to be filled again.
  signal dry_s : unsigned(22 downto 0);
  signal restarts_s : unsigned(7 downto 0);

  -- How far the buffer swung over a window.  A depth read on its own
  -- says nothing -- a link delivers frames in bursts and the converter
  -- takes them evenly, so it is always moving -- but a swing that stays
  -- between the same two marks is what says the two ends really do run
  -- at one rate.  One that walks means they do not.
  -- Twelve rather than the ten a depth of this size needs, so that the
  -- value reads as three hex digits.
  constant fifo_bits_c : natural := 12;
  signal fifo_window_s : unsigned(26 downto 0);
  signal fifo_min_run_s, fifo_max_run_s : unsigned(fifo_bits_c-1 downto 0);
  signal fifo_min_s, fifo_max_s : unsigned(fifo_bits_c-1 downto 0);

  -- These settle once a window and are then still for a second and a
  -- half, which is what lets them cross on a plain resynchroniser: it
  -- is told to take a value only once it has stopped changing.
  -- One character per step, and the step is what meter_level states.
  constant meter_width_c : natural := panel_columns_c - 2;
  constant meter_bits_c : natural := 5;

  constant snapshot_bits_c : natural := 2 * fifo_bits_c + 8 + 2 * meter_bits_c;
  signal snapshot_s, snapshot_crossed_s
    : std_ulogic_vector(snapshot_bits_c-1 downto 0);
  signal held_min_s, held_max_s : unsigned(fifo_bits_c-1 downto 0);
  signal held_lost_s : unsigned(7 downto 0);
  signal held_peak_a_s, held_peak_b_s : unsigned(meter_bits_c-1 downto 0);

  signal i2s_ready_s, i2s_channel_s : std_ulogic;
  signal i2s_sample_s : unsigned(audio_config_c.sample_bits-1 downto 0);
  signal i2s_slot_s : unsigned(slot_bits_c-1 downto 0);

  -- Frames the link brought in and frames the converter took, each
  -- counted where it happens and read once a second on the board's
  -- clock.  The two say the same number when the converter is being
  -- clocked at the rate the source stated, which is the whole claim
  -- this design makes.
  constant rate_counter_bits_c : natural := 24;
  signal in_count_s, out_count_s : unsigned(rate_counter_bits_c-1 downto 0);
  signal in_seen_s, out_seen_s : unsigned(rate_counter_bits_c-1 downto 0);
  signal in_last_s, out_last_s : unsigned(rate_counter_bits_c-1 downto 0);
  signal in_rate_s, out_rate_s : unsigned(rate_counter_bits_c-1 downto 0);
  -- The two rates agreeing is the whole claim, so it is shown as one
  -- bit rather than left to be read off two numbers.
  signal rate_match_s : std_ulogic;
  signal second_s : natural range 0 to clk_hz_c-1;

  -- Loudest sample of the window, kept as the bits that were ever set
  -- rather than as a maximum: the highest one of those is the level in
  -- steps of six decibels, which is what a meter wants anyway.
  signal peak_window_s : unsigned(20 downto 0);
  signal peak_run_a_s, peak_run_b_s : unsigned(23 downto 0);
  signal peak_a_s, peak_b_s : unsigned(meter_bits_c-1 downto 0);

  -- Islands and audio frames, counted a video frame at a time so that
  -- what is shown is a rate and not a total that only ever grows.
  signal vsync_prev_s : std_ulogic;
  signal island_run_s, island_frame_s : unsigned(15 downto 0);
  signal sample_run_s, sample_frame_s : unsigned(15 downto 0);

  constant line_length_c : natural := 123;
  constant uart_divisor_c : natural := clk_hz_c / 115200 - 1;
  signal line_s : byte_string(0 to line_length_c-1);
  signal tx_index_s : natural range 0 to line_length_c;
  signal tx_gap_s : unsigned(24 downto 0);
  signal tx_valid_s, tx_ready_s : std_ulogic;

  signal panel_s : nsl_video.pixel_stream.bus_t;
  signal panel_synced_s : std_ulogic;

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

  -- Where a sample sits, in steps of about a decibel and a half.
  --
  -- The highest bit set says it in sixes of a decibel, which is a scale
  -- so wide that everything worth hearing crowds into its last few
  -- places: a bar drawn straight off it is nearly full for anything
  -- audible and full for anything loud.  Two more bits taken from under
  -- that one quarter each step, and only the top of the range is drawn,
  -- so what the bar shows is the thirty six decibels below full scale
  -- rather than all hundred and forty four.
  function meter_level(v: unsigned; width: natural) return natural
  is
    alias a: unsigned(v'length-1 downto 0) is v;
    variable top, frac, level, floor_c: natural;
  begin
    top := 0;
    frac := 0;

    for i in 0 to a'left
    loop
      if a(i) = '1' then
        top := i + 1;

        if i >= 2 then
          frac := to_integer(a(i-1 downto i-2));
        else
          frac := 0;
        end if;
      end if;
    end loop;

    if top = 0 then
      return 0;
    end if;

    level := 4 * (top - 1) + frac;
    -- What a full scale sample comes to, less the bar's own length
    floor_c := 4 * a'length - 1 - width;

    if level <= floor_c then
      return 0;
    end if;

    return level - floor_c;
  end function;

  -- That many characters.
  function bar(n: unsigned; width: natural) return string
  is
    variable ret: string(1 to width) := (others => ' ');
  begin
    for i in 1 to width
    loop
      exit when i > to_integer(n);
      ret(i) := '#';
    end loop;

    return ret;
  end function;

  -- The magnitude of a sample, near enough for a meter: a negative one
  -- is turned over rather than negated, which is out by one bit at the
  -- bottom and never by a whole step.
  function magnitude(v: unsigned) return unsigned
  is
  begin
    if v(v'left) = '1' then
      return not v;
    end if;
    return v;
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

  -- Audio needs an HDMI link to travel on, and a link is only an HDMI
  -- one because a sink said so here.  Two channels is what an audio
  -- sample packet carries without anything further being asked for,
  -- and the rates offered are the three every source can send -- all
  -- of which this can clock, since the master clock is 256 times
  -- whichever one arrives.
  edid: nsl_dvi.ddc.ddc_edid_slave
    generic map(
      modes_c => modes_c,
      manufacturer_c => "NSL",
      product_code_c => 5,
      name_c => "NSL Audio",
      h_size_mm_c => 304,
      v_size_mm_c => 228,
      hdmi_c => true,
      audio_channels_c => 2
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
      serial_clock_o => open,
      locked_o => rx_locked_s,

      aligned_o => rx_aligned_s,
      control_o => rx_control_s,

      tmds_o => tmds_s
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

      tmds_i => tmds_s,

      period_o => period_s,
      pixel_o => open,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => di_hdr_s,
      di_data_o => di_data_s
      );

  de_s <= '1' when period_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA else '0';

  -- Nothing is drawn, but what the raster measures is how one tells at
  -- a glance that the link is the mode it was asked for.
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

  packets: nsl_hdmi.decoder.data_island_receiver
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,

      period_i => period_s,
      di_hdr_i => di_hdr_s,
      di_data_i => di_data_s,

      valid_o => packet_valid_s,
      packet_o => packet_s,
      error_o => packet_error_s
      );

  sound: nsl_hdmi.audio.hdmi_audio_receiver
    port map(
      reset_n_i => pixel_reset_n_s,
      clock_i => pixel_clock_s,

      valid_i => packet_valid_s,
      error_i => packet_error_s,
      packet_i => packet_s,

      acr_valid_o => acr_valid_s,
      cts_o => acr_cts_s,
      n_o => acr_n_s,

      valid_o => audio_valid_s,
      a_o => audio_a_s,
      b_o => audio_b_s,
      block_start_o => audio_block_s,
      flat_o => open
      );

  audio_clock: nsl_hdmi.audio.hdmi_audio_clock_recovery
    generic map(
      mclk_ratio_c => mclk_ratio_c
      )
    port map(
      reset_n_i => pixel_reset_n_s,
      clock_i => pixel_clock_s,

      valid_i => acr_valid_s,
      cts_i => acr_cts_s,
      n_i => acr_n_s,

      ready_o => acr_ready_s,
      mclk_tick_o => mclk_tick_s,
      sample_tick_o => open
      );

  -- A tick makes one edge of the master clock, and one tick in four
  -- goes on to make the bit and word clocks.  Taking both off the one
  -- counter is what keeps the converter settled: it works out what
  -- rate it is being fed by counting master clocks in a word clock
  -- period, and two counters at the same average rate would not give
  -- it the same answer twice.
  audio_clocks: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      i2s_tick_s <= '0';

      if mclk_tick_s = '1' then
        mclk_s <= not mclk_s;

        if tick_divider_s = i2s_tick_divisor_c-1 then
          tick_divider_s <= 0;
          i2s_tick_s <= playing_s;
        else
          tick_divider_s <= tick_divider_s + 1;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      mclk_s <= '0';
      i2s_tick_s <= '0';
      tick_divider_s <= 0;
    end if;
  end process;

  -- A converter is brought up in the order its datasheet asks for: the
  -- master clock first, which is what powers it up and sets its outputs
  -- ramping, and the word clock only once there is something to play.
  -- Starting both together would play an empty buffer, and the buffer
  -- is where a link's burstiness is absorbed -- half full leaves as
  -- much room for a late frame as for an early one.
  --
  -- Where the buffer settles is decided once and then kept, because the
  -- two ends run at one rate: nothing pushes it back up afterwards.  So
  -- a link that hiccups once while it is starting -- a source getting
  -- its own output going, say -- leaves the buffer on the floor for as
  -- long as the link lasts, one late frame away from a gap every time.
  --
  -- The answer is to fill it again, which means taking the word clock
  -- away and giving it back.  A converter takes that as a rate to work
  -- out afresh, which is what it does after any interruption, and it
  -- holds its outputs at zero while it does rather than jumping.  The
  -- master clock is left running throughout, so it never powers down.
  bring_up: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      -- A buffer this shallow is not a burst going by, it is a buffer
      -- that has nothing left to give.  Timing it rather than acting on
      -- the depth itself is what keeps an ordinary burst from counting.
      if fifo_level_s >= fifo_depth_c / 8 then
        dry_s <= (others => '0');
      elsif dry_s(dry_s'left) = '0' then
        dry_s <= dry_s + 1;
      end if;

      if dry_s(dry_s'left) = '1' then
        playing_s <= '0';

        if playing_s = '1' then
          restarts_s <= restarts_s + 1;
        end if;
      elsif fifo_level_s >= fifo_depth_c / 2 then
        playing_s <= '1';

        if playing_s = '0' then
          start_level_s <= to_unsigned(fifo_level_s, start_level_s'length);
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      playing_s <= '0';
      start_level_s <= (others => '0');
      dry_s <= (others => '0');
      restarts_s <= (others => '0');
    end if;
  end process;

  i2s_clocks: nsl_i2s.clock.i2s_clock_generator_from_tick
    generic map(
      tick_per_sample_c => 128
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      tick_i => i2s_tick_s,

      sck_o => sck_s,
      ws_o => ws_s
      );

  -- A source sends samples as soon as it has any, and says how fast
  -- they were meant to come out in a packet of its own which may not
  -- arrive for several frames.  Samples that turn up before it are
  -- dropped rather than kept: there is nothing yet to play them at, and
  -- keeping them fills the buffer to the brim before anything can start
  -- draining it, leaving it pinned there for as long as the link lasts.
  --
  -- What the buffer wants instead is to start empty at the moment the
  -- converter is about to start, so that it settles half full and has
  -- as much room for a late frame as for an early one.
  audio_taken_s <= audio_valid_s and acr_ready_s;

  -- From here on the audio is no longer HDMI's, it is frames on a
  -- stream, and what carries it to the converter is the same FIFO
  -- anything else would use.
  source: nsl_hdmi.audio_stream.hdmi_audio_stream_source
    generic map(
      config_c => audio_config_c
      )
    port map(
      reset_n_i => pixel_reset_n_s,
      clock_i => pixel_clock_s,

      valid_i => audio_taken_s,
      a_i => audio_a_s,
      b_i => audio_b_s,
      block_start_i => audio_block_s,

      out_o => audio_s.m,
      out_i => audio_s.s,

      overflow_o => overflow_s
      );

  -- One clock, because the converter runs off the link's own rate:
  -- there is no second domain here and nothing to reconcile.
  buffering: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => audio_config_c.stream,
      depth_c => fifo_depth_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      in_i => audio_s.m,
      in_o => audio_s.s,
      in_free_o => open,

      out_o => played_s.m,
      out_i => played_s.s,
      out_available_o => fifo_level_s
      );

  player: nsl_i2s.stream.i2s_stream_transmitter
    generic map(
      config_c => audio_config_c
      )
    port map(
      reset_n_i => pixel_reset_n_s,
      clock_i => pixel_clock_s,

      in_i => played_s.m,
      in_o => played_s.s,

      ready_i => i2s_ready_s,
      channel_i => i2s_channel_s,
      data_o => i2s_sample_s,

      underflow_o => underflow_s
      );

  -- The sample sits at the top of the slot, which is where a converter
  -- reading twenty four bits of a thirty two bit half frame looks for
  -- it.  What follows it is shifted out and ignored.
  i2s_slot_s <= i2s_sample_s & to_unsigned(0, slot_bits_c - i2s_sample_s'length);

  dac: nsl_digilent.pmod_i2s2.pmod_i2s2_line_out_driver
    port map(
      pmod_io => j5_io,

      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      mclk_i => mclk_s,
      sck_i => sck_s,
      ws_i => ws_s,

      ready_o => i2s_ready_s,
      channel_o => i2s_channel_s,
      data_i => i2s_slot_s
      );

  -- What the link brought and what the converter took, each counted
  -- where it happens.  A frame is taken once its second channel has
  -- been asked for.
  counters: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      if audio_valid_s = '1' then
        in_count_s <= in_count_s + 1;
      end if;

      if i2s_ready_s = '1' and i2s_channel_s = '1' then
        out_count_s <= out_count_s + 1;
      end if;

      if overflow_s = '1' or underflow_s = '1' then
        lost_s <= lost_s + 1;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      in_count_s <= (others => '0');
      out_count_s <= (others => '0');
      lost_s <= (others => '0');
    end if;
  end process;

  in_cross: nsl_clocking.interdomain.interdomain_counter
    generic map(
      data_width_c => rate_counter_bits_c
      )
    port map(
      clock_in_i => pixel_clock_s,
      clock_out_i => clock_s,
      data_i => in_count_s,
      data_o => in_seen_s
      );

  out_cross: nsl_clocking.interdomain.interdomain_counter
    generic map(
      data_width_c => rate_counter_bits_c
      )
    port map(
      clock_in_i => pixel_clock_s,
      clock_out_i => clock_s,
      data_i => out_count_s,
      data_o => out_seen_s
      );

  rates: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if second_s = 0 then
        second_s <= clk_hz_c-1;
        in_last_s <= in_seen_s;
        out_last_s <= out_seen_s;
        in_rate_s <= in_seen_s - in_last_s;
        out_rate_s <= out_seen_s - out_last_s;
      else
        second_s <= second_s - 1;
      end if;
    end if;

    if reset_n_s = '0' then
      second_s <= clk_hz_c-1;
      in_last_s <= (others => '0');
      out_last_s <= (others => '0');
      in_rate_s <= (others => '0');
      out_rate_s <= (others => '0');
    end if;
  end process;

  fifo_watch: process(pixel_clock_s, pixel_reset_n_s) is
    variable level: unsigned(fifo_bits_c-1 downto 0);
  begin
    if rising_edge(pixel_clock_s) then
      level := to_unsigned(fifo_level_s, fifo_bits_c);
      fifo_window_s <= fifo_window_s + 1;

      if fifo_window_s = 0 then
        fifo_min_s <= fifo_min_run_s;
        fifo_max_s <= fifo_max_run_s;
        fifo_min_run_s <= level;
        fifo_max_run_s <= level;
      else
        if level < fifo_min_run_s then
          fifo_min_run_s <= level;
        end if;

        if level > fifo_max_run_s then
          fifo_max_run_s <= level;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      fifo_window_s <= (others => '0');
      fifo_min_run_s <= (others => '1');
      fifo_max_run_s <= (others => '0');
      fifo_min_s <= (others => '0');
      fifo_max_s <= (others => '0');
    end if;
  end process;

  snapshot_s <= std_ulogic_vector(fifo_min_s)
                & std_ulogic_vector(fifo_max_s)
                & std_ulogic_vector(lost_s)
                & std_ulogic_vector(peak_a_s)
                & std_ulogic_vector(peak_b_s);

  snapshot_cross: nsl_clocking.interdomain.interdomain_reg
    generic map(
      stable_count_c => 16,
      data_width_c => snapshot_bits_c
      )
    port map(
      clock_i => clock_s,
      data_i => snapshot_s,
      data_o => snapshot_crossed_s
      );

  held_min_s <= unsigned(snapshot_crossed_s(snapshot_bits_c-1
                                            downto snapshot_bits_c-fifo_bits_c));
  held_max_s <= unsigned(snapshot_crossed_s(snapshot_bits_c-fifo_bits_c-1
                                            downto 2*meter_bits_c+8));
  held_lost_s <= unsigned(snapshot_crossed_s(2*meter_bits_c+7
                                             downto 2*meter_bits_c));
  held_peak_a_s <= unsigned(snapshot_crossed_s(2*meter_bits_c-1
                                               downto meter_bits_c));
  held_peak_b_s <= unsigned(snapshot_crossed_s(meter_bits_c-1 downto 0));

  meter: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      peak_window_s <= peak_window_s + 1;

      if peak_window_s = 0 then
        peak_a_s <= to_unsigned(meter_level(peak_run_a_s, meter_width_c),
                                meter_bits_c);
        peak_b_s <= to_unsigned(meter_level(peak_run_b_s, meter_width_c),
                                meter_bits_c);
        peak_run_a_s <= (others => '0');
        peak_run_b_s <= (others => '0');
      elsif audio_valid_s = '1' then
        peak_run_a_s <= peak_run_a_s or magnitude(audio_a_s.data);
        peak_run_b_s <= peak_run_b_s or magnitude(audio_b_s.data);
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      peak_window_s <= (others => '0');
      peak_run_a_s <= (others => '0');
      peak_run_b_s <= (others => '0');
      peak_a_s <= (others => '0');
      peak_b_s <= (others => '0');
    end if;
  end process;

  -- Islands and the audio frames they held, a video frame at a time.
  -- A DVI source sends no islands at all, an HDMI one carrying sound
  -- sends a few hundred, so this one number says which is happening.
  island_count: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      vsync_prev_s <= vsync_s;

      if vsync_s = '1' and vsync_prev_s = '0' then
        island_frame_s <= island_run_s;
        sample_frame_s <= sample_run_s;
        island_run_s <= (others => '0');
        sample_run_s <= (others => '0');
      else
        if period_s = nsl_dvi.dvi.PERIOD_DI_DATA and di_hdr_s(1) = '0' then
          island_run_s <= island_run_s + 1;
        end if;

        if audio_valid_s = '1' then
          sample_run_s <= sample_run_s + 1;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      vsync_prev_s <= '0';
      island_run_s <= (others => '0');
      sample_run_s <= (others => '0');
      island_frame_s <= (others => '0');
      sample_frame_s <= (others => '0');
    end if;
  end process;

  panel_text: nsl_video.terminal.terminal_labels
    generic map(
      row_count_l2_c => 4,
      column_count_l2_c => 5,
      character_count_l2_c => 8,
      color_palette_c => palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => panel_labels_c,
      config_c => pixel_config_c,
      geometry_c => nsl_video.mode.geometry(160, 80)
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
  colors: for i in 0 to 7
  generate
    panel_color_s(i) <= to_unsigned(i, panel_color_s(i)'length);
  end generate;

  -- Everything below reads values that are kept in the link's clock
  -- domain.  They are shown rather than acted on, and they settle
  -- between one frame and the next, so a digit caught mid-change costs
  -- nothing.  The two rates are the exception and cross properly: they
  -- are what says the design works.
  panel_text_s <= fit("NSL HDMI AUDIO", panel_columns_c)
                  & fit("LOCK " & yes(rx_locked_s)
                        & " ALIGN " & yes(rx_aligned_s(0))
                        & yes(rx_aligned_s(1)) & yes(rx_aligned_s(2)),
                        panel_columns_c)
                  & fit("MODE " & hex(timings_s.h.active, 4)
                        & "x" & hex(timings_s.v.active, 4)
                        & " " & yes(timings_valid_s), panel_columns_c)
                  & fit("ISL " & hex(island_frame_s, 4)
                        & " SMP " & hex(sample_frame_s, 4), panel_columns_c)
                  & fit("N " & hex(acr_n_s, 5)
                        & " CTS " & hex(acr_cts_s, 5), panel_columns_c)
                  & fit("IN " & hex(in_rate_s, 5)
                        & " OUT " & hex(out_rate_s, 5)
                        & " " & yes(rate_match_s), panel_columns_c)
                  & fit("BUF " & hex(held_min_s, 3)
                        & "-" & hex(held_max_s, 3)
                        & " LOST " & hex(held_lost_s, 2), panel_columns_c)
                  & fit("L " & bar(held_peak_a_s, meter_width_c),
                        panel_columns_c)
                  & fit("R " & bar(held_peak_b_s, meter_width_c),
                        panel_columns_c);

  line_s <= to_byte_string("L " & yes(rx_locked_s))
            & to_byte_string(" A " & yes(rx_aligned_s(0))
                             & yes(rx_aligned_s(1)) & yes(rx_aligned_s(2)))
            & to_byte_string(" M " & hex(timings_s.h.active, 4)
                             & "x" & hex(timings_s.v.active, 4))
            & to_byte_string(" ISL " & hex(island_frame_s, 4))
            & to_byte_string(" SMP " & hex(sample_frame_s, 4))
            & to_byte_string(" N " & hex(acr_n_s, 5))
            & to_byte_string(" CTS " & hex(acr_cts_s, 5))
            & to_byte_string(" CK " & yes(acr_ready_s))
            & to_byte_string(" IN " & hex(in_rate_s, 5))
            & to_byte_string(" OUT " & hex(out_rate_s, 5))
            & to_byte_string(" EQ " & yes(rate_match_s))
            & to_byte_string(" BUF " & hex(held_min_s, 3)
                             & "-" & hex(held_max_s, 3))
            & to_byte_string(" LOST " & hex(held_lost_s, 2))
            & to_byte_string(" P " & yes(playing_s))
            & to_byte_string(" S " & hex(start_level_s, 3))
            & to_byte_string(" R " & hex(restarts_s, 2))
            & to_byte_string("" & cr & lf);

  report_gen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if tx_index_s = line_length_c then
        tx_gap_s <= tx_gap_s + 1;
        if tx_gap_s(tx_gap_s'left) = '1' then
          tx_gap_s <= (others => '0');
          tx_index_s <= 0;
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

  rate_match_s <= '1' when in_rate_s = out_rate_s and in_rate_s /= 0 else '0';

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
  -- Lit once a source has said what rate it is sending at, which is
  -- what the converter is waiting for.
  done_led_o <= acr_ready_s;

end arch;
