library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_dvi, nsl_hdmi, nsl_i2c, nsl_video,
  nsl_sipeed, nsl_digilent, nsl_uart, nsl_line_coding, nsl_data;
use nsl_data.bytestream.all;
-- For the equality on a symbol period and on a set of timings
use nsl_dvi.dvi.all;
use nsl_video.mode.all;

-- Half a DVI sink: the half that says a sink is there and answers what
-- it is.  No TMDS is looked at here.
--
-- A source sends nothing until it sees hot plug detect asserted and
-- reads an EDID it likes, so this comes first, and is provable from
-- the source's end alone: a display appears and reads back as 640x480
-- at 60.
--
-- The eight LEDs on J5 say where things got to.  Two of them blink,
-- which is what tells a design that is running from one that is not
-- whichever way round the LEDs are wired:
--
--   1  heartbeat off the internal oscillator: the bitstream is loaded
--   2  reset has been released
--   3  the PLL made a clock out of the link's, and every lane found
--      where its symbols start
--   4  the decoder is seeing video periods
--   5  the raster has been measured and settled
--   6  the frame is as wide as the mode says
--   7  the frame is as tall as the mode says
--   8  every timing matches the mode that was advertised
--
-- 8 is the one that matters: it says a frame came off the wire with
-- the blanking and sync polarities the mode states, which is the
-- whole path from pads to raster working.
--
-- What was actually measured goes out of the UART at 115200 8N1,
-- twice a second, as
--
--   L<lock><align> C <link hz> H <act> <blank> <off> <width> <pol>
--   V <act> <blank> <off> <width> <pol> D <islands> A <audio>
--   E <bad parity> T <types seen>
--   P <video symbols> <island symbols> <vsync edges> <video starts>
--     <island preamble> <video preamble>
--   N <n> <cts> S <samples a frame> <ticks a frame>
--
-- N and CTS are how a source states its audio rate: they mean
-- 128 * fs = link clock * N / CTS, and nothing in the samples says it.
-- The two counts after them are the samples a frame actually carried
-- and the ticks the clock built from that statement made over the
-- same frame.  They are arrived at from opposite ends, so their
-- meeting is the rate being right.
--
-- The three after P are counted over a fixed window of a million
-- symbols rather than over a frame.  A frame is a poor thing to count
-- between when the question is whether frames are arriving at all: a
-- source driving sync and nothing else has no frame boundaries, and
-- these say so where the raster above can only shrug.
--
-- in hex, on one line.  A yes or no only says the answer is wrong;
-- the numbers say what it is wrong by.  The link rate is counted
-- against the board clock, so it says which mode is arriving whatever
-- the raster below makes of it.
--
-- The islands count is what says the link is an HDMI one: a DVI
-- source sends none, and an HDMI source carrying audio sends a few
-- hundred a frame.  What those islands held follows: how many were
-- audio samples, how many failed their parity, and one bit for every
-- packet type that went by -- the low half of the word for types 0x00
-- to 0x0f, the high half for the infoframes at 0x80 to 0x8f.  It is read across clock domains without being
-- resynchronised, as the timings are -- the numbers sit still for
-- whole seconds at a time, so a torn read is rare and costs nothing
-- but one odd line.
--
-- Lanes are aligned to themselves and not to each other.  At 720p a
-- symbol lasts 13.5ns and a cable puts a nanosecond or two between
-- pairs, so they should already be within a symbol of each other; 8
-- lighting is what says so.  That margin is what shrinks as modes get
-- faster, and what data islands care about more than pixels do: a
-- lane out by one symbol only shifts a colour, but it wrecks every
-- packet.
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

    j5_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;

  -- What this sink can receive, and therefore all it advertises.  A
  -- source cannot pick a mode that is not on offer, so offering only
  -- what the deserialiser will keep up with is what keeps it honest:
  -- the serial rate is five times the pixel clock, 125.9 MHz here.
  constant modes_c : nsl_video.mode.mode_vector(0 to 0)
    := (0 => nsl_video.mode.mode_std_1280x720p60_c);

  -- Low long enough for a source to notice the sink went, then high
  -- long enough for it to read before it goes again.
  constant hpd_period_l2_c : natural := 27;

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;
  signal osc_s : std_ulogic;

  signal ddc_i_s : nsl_i2c.i2c.i2c_i;
  signal ddc_o_s : nsl_i2c.i2c.i2c_o;
  signal selected_s : std_ulogic;

  signal hpd_s : std_ulogic;
  signal hpd_cycle_s : unsigned(hpd_period_l2_c-1 downto 0);

  signal addressed_s : std_ulogic;

  -- Rate of the clock pair, which cannot exceed the reference
  signal tmds_rate_s : unsigned(26 downto 0);

  signal pixel_reset_n_s : std_ulogic;
  signal period_s : nsl_dvi.dvi.period_t;
  signal de_s, hsync_s, vsync_s : std_ulogic;
  signal timings_s : nsl_video.mode.timings_t;
  signal timings_valid_s : std_ulogic;

  constant expected_c : nsl_video.mode.timings_t
    := nsl_video.mode.timings(modes_c(0));

  -- What goes out of the UART, and what it is built from once a line
  constant line_length_c : natural := 171;
  constant uart_divisor_c : natural := clk_hz_c / 115200 - 1;

  signal held_s : nsl_video.mode.timings_t;
  signal held_lock_s, held_align_s : std_ulogic;
  -- The link's own rate in Hz, which says what mode is arriving
  -- whatever the raster below makes of it.  Reported as it is
  -- counted: dividing it down to something friendlier costs a
  -- divider, and this clock has none to spare.
  signal held_hz_s : unsigned(31 downto 0);

  -- Data islands per frame, which is zero on a DVI link and a few
  -- hundred on an HDMI one carrying audio.
  signal di_hdr_s : std_ulogic_vector(1 downto 0);
  signal di_data_s : std_ulogic_vector(7 downto 0);
  signal di_count_s, di_frame_s, held_di_s : unsigned(15 downto 0);
  signal vsync_d_s : std_ulogic;

  -- What the islands turned out to hold, counted a frame at a time.
  -- The audio count is the one that says a link is carrying sound and
  -- at what rate: 44.1 kHz puts 735 samples in a 60 Hz frame.
  -- Counted over a fixed window rather than over a frame, so they
  -- still say something when there are no frames: a link with no
  -- vsync edges has no frame boundaries to count between, and that is
  -- exactly the case worth being able to see.
  signal probe_window_s : unsigned(19 downto 0);
  signal video_run_s, video_hold_s, held_video_s : unsigned(31 downto 0);
  signal island_run_s, island_hold_s, held_island_s : unsigned(31 downto 0);
  signal vedge_run_s, vedge_hold_s, held_vedge_s : unsigned(15 downto 0);
  -- Times video data started in the window.  One a line is a raster;
  -- many a line is a link dropping out of video and back into it,
  -- which is what a symbol arriving wrong looks like from here.
  signal dedge_run_s, dedge_hold_s, held_dedge_s : unsigned(15 downto 0);
  signal de_d_s : std_ulogic;
  -- Symbols spent announcing a period.  A line announces video once
  -- and, on a link carrying islands, an island once, so these say
  -- whether an announcement was heard at all -- which is a different
  -- failure from hearing it and then losing what it announced.
  signal dipre_run_s, dipre_hold_s, held_dipre_s : unsigned(15 downto 0);
  -- Symbols lane 0 holds that are plain pixel data, counted below the
  -- state machine.  What a link carries and what a decoder makes of it
  -- are different questions, and this asks the first one.
  signal lane0_de_s, lane0_terc4_s : std_ulogic;
  signal lane0_pixel_s : unsigned(7 downto 0);
  signal lane0_control_s : std_ulogic_vector(3 downto 0);

  -- A still picture sends the same bytes every frame, so a lane whose
  -- sum over a frame keeps changing is a lane taking bits wrong.  A
  -- packing mistake would give the wrong answer and give it steadily.
  -- During a control period every lane carries a control word, and a
  -- decoder says so by holding de low.  A lane holding it high there
  -- is carrying something that is not a control word, which nothing
  -- correct does.
  --
  -- Counting it the other way round -- control words during video --
  -- proves nothing, because a decoder calls anything that is neither
  -- control nor TERC4 pixel data.  A lane taking bits wrong mostly
  -- produces symbols that are no code at all, and those come back
  -- looking exactly like pixels.
  type lane_count_vector is array(natural range <>) of unsigned(15 downto 0);
  signal lane_bad_s, lane_bad_hold_s, held_bad_s : lane_count_vector(0 to 2);
  signal lane_de_s, lane_terc4_s : std_ulogic_vector(0 to 2);
  signal decoded_pixel_s : nsl_data.bytestream.byte_string(0 to 2);
  signal data_run_s, data_hold_s, held_data_s : unsigned(31 downto 0);
  -- Times lane 0 went from carrying something else to carrying pixel
  -- data, counted on the wire rather than on what a state machine made
  -- of it.  One a line is a clean link; more is a link dropping bits.
  signal lane0_de_d_s : std_ulogic;
  signal redge_run_s, redge_hold_s, held_redge_s : unsigned(15 downto 0);
  signal vidpre_run_s, vidpre_hold_s, held_vidpre_s : unsigned(15 downto 0);

  signal rx_valid_s, rx_error_s : std_ulogic;
  signal rx_packet_s : nsl_hdmi.hdmi.data_island_t;
  signal audio_count_s, audio_frame_s, held_audio_s : unsigned(15 downto 0);
  signal err_count_s, err_frame_s, held_err_s : unsigned(15 downto 0);
  -- One bit a packet type, the low half for types 0x00 to 0x0f and
  -- the high half for the infoframes at 0x80 to 0x8f
  signal seen_s, seen_frame_s, held_seen_s : std_ulogic_vector(31 downto 0);

  -- The rate a source states, and two ways of counting what it means.
  -- Samples come from the packets and ticks from the clock the stated
  -- rate builds, so the two agreeing is the rate being right rather
  -- than merely arriving.
  signal audio_valid_s, acr_valid_s : std_ulogic;
  signal acr_n_s, acr_cts_s : unsigned(19 downto 0);
  signal held_n_s, held_cts_s : unsigned(19 downto 0);
  signal sample_tick_s : std_ulogic;
  signal samples_s, samples_frame_s, held_samples_s : unsigned(15 downto 0);
  signal ticks_s, ticks_frame_s, held_ticks_s : unsigned(15 downto 0);

  signal line_s : byte_string(0 to line_length_c-1);
  signal tx_index_s : natural range 0 to line_length_c;
  signal tx_gap_s : unsigned(24 downto 0);
  signal tx_valid_s, tx_ready_s : std_ulogic;

  function hex4(v: unsigned) return byte_string
  is
    -- Taken however the caller numbered it
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

  signal pixel_clock_s : std_ulogic;
  signal rx_locked_s : std_ulogic;
  signal rx_aligned_s, rx_control_s : std_ulogic_vector(0 to 2);
  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;



  signal osc_beat_s : unsigned(24 downto 0);

  signal led_s : std_ulogic_vector(1 to 8);

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  -- An oscillator of its own, so a dead board clock still shows a
  -- loaded bitstream rather than nothing at all.
  osc: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => osc_s
      );

  osc_beat: process(osc_s) is
  begin
    if rising_edge(osc_s) then
      osc_beat_s <= osc_beat_s + 1;
    end if;
  end process;

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

  edid: nsl_dvi.ddc.ddc_edid_slave
    generic map(
      modes_c => modes_c,
      manufacturer_c => "NSL",
      product_code_c => 1,
      name_c => "NSL Capture",
      -- A 15 inch 4:3 panel, so a source works out a sane density
      h_size_mm_c => 304,
      v_size_mm_c => 228,
      -- Ask for an HDMI link, which is what makes a source send data
      -- islands at all, and for two channels of audio to fill them
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

  -- What the clock pair is doing, counted against the board clock
  rate: nsl_clocking.interdomain.clock_rate_measurer
    generic map(
      clock_i_hz_c => clk_hz_c,
      update_hz_l2_c => 2
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      measured_clock_i => dvi_ck_i,
      rate_hz_o => tmds_rate_s
      );

  ddc_pads: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.scl => dvi_ddc_scl_io,
      bus_io.sda => dvi_ddc_sda_io,
      bus_o => ddc_i_s,
      bus_i => ddc_o_s
      );

  -- Appearing: the line is left low for a moment, then asserted, so a
  -- source that was already running sees a sink arrive.
  hotplug: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then

      -- Appearing and disappearing until somebody reads us, then
      -- staying
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

  led_s(1) <= osc_beat_s(osc_beat_s'left);
  led_s(2) <= reset_n_s;
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

  -- Straight from the link's own clock domain: a LED does not mind
  -- catching a signal mid-change.
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
      pixel_o => decoded_pixel_s,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => di_hdr_s,
      di_data_o => di_data_s
      );

  packets: nsl_hdmi.decoder.data_island_receiver
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,

      period_i => period_s,
      di_hdr_i => di_hdr_s,
      di_data_i => di_data_s,

      valid_o => rx_valid_s,
      packet_o => rx_packet_s,
      error_o => rx_error_s
      );

  de_s <= '1' when period_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA else '0';

  -- Islands counted a frame at a time, so what is reported is a rate
  -- rather than a total that only ever grows.  The island's first
  -- symbol is what marks one, and a frame ends wherever vsync goes
  -- up, whichever way round the mode states it.
  island_count: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      vsync_d_s <= vsync_s;

      if vsync_s = '1' and vsync_d_s = '0' then
        di_frame_s <= di_count_s;
        di_count_s <= (others => '0');
      elsif period_s = nsl_dvi.dvi.PERIOD_DI_DATA and di_hdr_s(1) = '0' then
        di_count_s <= di_count_s + 1;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      di_count_s <= (others => '0');
      di_frame_s <= (others => '0');
      vsync_d_s <= '0';
    end if;
  end process;

  lane0: nsl_line_coding.tmds.tmds_decoder
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      symbol_i => tmds_s(0),

      de_o => lane0_de_s,
      pixel_o => lane0_pixel_s,
      terc4_o => lane0_terc4_s,
      control_o => lane0_control_s
      );

  -- All three, so what one lane does can be held against another
  lanes: for i in 0 to 2
  generate
    one: nsl_line_coding.tmds.tmds_decoder
      port map(
        clock_i => pixel_clock_s,
        reset_n_i => pixel_reset_n_s,

        symbol_i => tmds_s(i),

        de_o => lane_de_s(i),
        pixel_o => open,
        terc4_o => lane_terc4_s(i),
        control_o => open
        );
  end generate;

  -- The decoder's own pixel bytes, summed over a frame


  lane_errors: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      if probe_window_s = 0 then
        for i in 0 to 2
        loop
          lane_bad_hold_s(i) <= lane_bad_s(i);
          lane_bad_s(i) <= (others => '0');
        end loop;
      elsif period_s = nsl_dvi.dvi.PERIOD_CONTROL then
        for i in 0 to 2
        loop
          if lane_de_s(i) = '1' then
            lane_bad_s(i) <= lane_bad_s(i) + 1;
          end if;
        end loop;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      for i in 0 to 2
      loop
        lane_bad_s(i) <= (others => '0');
        lane_bad_hold_s(i) <= (others => '0');
      end loop;
    end if;
  end process;

  probe: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      probe_window_s <= probe_window_s + 1;
      lane0_de_d_s <= lane0_de_s;

      if probe_window_s = 0 then
        video_hold_s <= video_run_s;
        island_hold_s <= island_run_s;
        vedge_hold_s <= vedge_run_s;
        dedge_hold_s <= dedge_run_s;
        data_hold_s <= data_run_s;
        redge_hold_s <= redge_run_s;
        data_run_s <= (others => '0');
        redge_run_s <= (others => '0');
        dipre_hold_s <= dipre_run_s;
        vidpre_hold_s <= vidpre_run_s;
        dipre_run_s <= (others => '0');
        vidpre_run_s <= (others => '0');
        video_run_s <= (others => '0');
        island_run_s <= (others => '0');
        vedge_run_s <= (others => '0');
        dedge_run_s <= (others => '0');
      else
        if period_s = nsl_dvi.dvi.PERIOD_VIDEO_DATA then
          video_run_s <= video_run_s + 1;
        end if;
        if period_s = nsl_dvi.dvi.PERIOD_DI_DATA then
          island_run_s <= island_run_s + 1;
        end if;
        if vsync_s = '1' and vsync_d_s = '0' then
          vedge_run_s <= vedge_run_s + 1;
        end if;
        if de_s = '1' and de_d_s = '0' then
          dedge_run_s <= dedge_run_s + 1;
        end if;
        if period_s = nsl_dvi.dvi.PERIOD_DI_PRE then
          dipre_run_s <= dipre_run_s + 1;
        end if;
        if period_s = nsl_dvi.dvi.PERIOD_VIDEO_PRE then
          vidpre_run_s <= vidpre_run_s + 1;
        end if;
        -- Pixel data rather than a control word or a TERC4 one
        if lane0_de_s = '1' and lane0_terc4_s = '0' then
          data_run_s <= data_run_s + 1;
        end if;
        if lane0_de_s = '1' and lane0_de_d_s = '0' then
          redge_run_s <= redge_run_s + 1;
        end if;
      end if;

      de_d_s <= de_s;
    end if;

    if pixel_reset_n_s = '0' then
      probe_window_s <= (others => '0');
      video_run_s <= (others => '0');
      island_run_s <= (others => '0');
      vedge_run_s <= (others => '0');
      video_hold_s <= (others => '0');
      island_hold_s <= (others => '0');
      vedge_hold_s <= (others => '0');
      dedge_run_s <= (others => '0');
      dedge_hold_s <= (others => '0');
      de_d_s <= '0';
      dipre_run_s <= (others => '0');
      dipre_hold_s <= (others => '0');
      vidpre_run_s <= (others => '0');
      vidpre_hold_s <= (others => '0');
      data_run_s <= (others => '0');
      data_hold_s <= (others => '0');
      redge_run_s <= (others => '0');
      redge_hold_s <= (others => '0');
      lane0_de_d_s <= '0';
    end if;
  end process;

  sound: nsl_hdmi.audio.hdmi_audio_receiver
    port map(
      reset_n_i => pixel_reset_n_s,
      clock_i => pixel_clock_s,

      valid_i => rx_valid_s,
      error_i => rx_error_s,
      packet_i => rx_packet_s,

      acr_valid_o => acr_valid_s,
      cts_o => acr_cts_s,
      n_o => acr_n_s,

      valid_o => audio_valid_s,
      a_o => open,
      b_o => open,
      block_start_o => open,
      flat_o => open
      );

  audio_clock: nsl_hdmi.audio.hdmi_audio_clock_recovery
    port map(
      reset_n_i => pixel_reset_n_s,
      clock_i => pixel_clock_s,

      valid_i => acr_valid_s,
      cts_i => acr_cts_s,
      n_i => acr_n_s,

      ready_o => open,
      mclk_tick_o => open,
      sample_tick_o => sample_tick_s
      );

  -- Samples a frame carried, against ticks the recovered clock made
  -- over the same frame.  A source sends samples as it pleases and the
  -- clock runs off what it stated, so the two meeting is what says the
  -- statement was true.
  sound_count: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      if acr_valid_s = '1' then
        held_n_s <= acr_n_s;
        held_cts_s <= acr_cts_s;
      end if;

      if vsync_s = '1' and vsync_d_s = '0' then
        samples_frame_s <= samples_s;
        ticks_frame_s <= ticks_s;
        samples_s <= (others => '0');
        ticks_s <= (others => '0');
      else
        if audio_valid_s = '1' then
          samples_s <= samples_s + 1;
        end if;
        if sample_tick_s = '1' then
          ticks_s <= ticks_s + 1;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      held_n_s <= (others => '0');
      held_cts_s <= (others => '0');
      samples_s <= (others => '0');
      ticks_s <= (others => '0');
      samples_frame_s <= (others => '0');
      ticks_frame_s <= (others => '0');
    end if;
  end process;

  -- What the packets are, over the same frame.  A type is recorded by
  -- the bit its number picks out, so one line says everything the
  -- link carried rather than only the last thing it carried.
  packet_count: process(pixel_clock_s, pixel_reset_n_s) is
    variable at : natural range 0 to 31;
  begin
    if rising_edge(pixel_clock_s) then
      if vsync_s = '1' and vsync_d_s = '0' then
        audio_frame_s <= audio_count_s;
        err_frame_s <= err_count_s;
        seen_frame_s <= seen_s;
        audio_count_s <= (others => '0');
        err_count_s <= (others => '0');
        seen_s <= (others => '0');
      elsif rx_valid_s = '1' then
        if rx_packet_s.packet_type(7) = '1' then
          at := 16 + to_integer(unsigned(rx_packet_s.packet_type(3 downto 0)));
        else
          at := to_integer(unsigned(rx_packet_s.packet_type(3 downto 0)));
        end if;
        seen_s(at) <= '1';

        if rx_packet_s.packet_type = nsl_hdmi.hdmi.di_type_audio_sample then
          audio_count_s <= audio_count_s + 1;
        end if;

        if rx_error_s = '1' then
          err_count_s <= err_count_s + 1;
        end if;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      audio_count_s <= (others => '0');
      audio_frame_s <= (others => '0');
      err_count_s <= (others => '0');
      err_frame_s <= (others => '0');
      seen_s <= (others => '0');
      seen_frame_s <= (others => '0');
    end if;
  end process;

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

  led_s(3) <= rx_locked_s and rx_aligned_s(0) and rx_aligned_s(1)
              and rx_aligned_s(2);
  led_s(4) <= de_s;
  led_s(5) <= timings_valid_s;
  led_s(6) <= '1' when timings_s.h.active = expected_c.h.active else '0';
  led_s(7) <= '1' when timings_s.v.active = expected_c.v.active else '0';
  led_s(8) <= '1' when timings_valid_s = '1' and timings_s = expected_c else '0';

  -- Held still while a line goes out, so what is reported is one
  -- frame's worth rather than pieces of two.
  line_s <= to_byte_string("L") & bit_char(held_lock_s) & bit_char(held_align_s)
            & to_byte_string(" C ") & hex4(held_hz_s(31 downto 16))
            & hex4(held_hz_s(15 downto 0))
            & to_byte_string(" H ")
            & hex4(held_s.h.active) & to_byte_string(" ")
            & hex4(held_s.h.blank) & to_byte_string(" ")
            & hex4(held_s.h.off) & to_byte_string(" ")
            & hex4(held_s.h.width) & to_byte_string(" ")
            & bit_char(held_s.h.sync)
            & to_byte_string(" V ")
            & hex4(held_s.v.active) & to_byte_string(" ")
            & hex4(held_s.v.blank) & to_byte_string(" ")
            & hex4(held_s.v.off) & to_byte_string(" ")
            & hex4(held_s.v.width) & to_byte_string(" ")
            & bit_char(held_s.v.sync)
            & to_byte_string(" D ") & hex4(held_di_s)
            & to_byte_string(" A ") & hex4(held_audio_s)
            & to_byte_string(" E ") & hex4(held_err_s)
            & to_byte_string(" T ") & hex4(unsigned(held_seen_s(31 downto 16)))
            & hex4(unsigned(held_seen_s(15 downto 0)))
            & to_byte_string(" P ") & hex4(held_video_s(31 downto 16))
            & hex4(held_video_s(15 downto 0))
            & to_byte_string(" ") & hex4(held_island_s(31 downto 16))
            & hex4(held_island_s(15 downto 0))
            & to_byte_string(" ") & hex4(held_vedge_s)
            & to_byte_string(" ") & hex4(held_dedge_s)
            & to_byte_string(" ") & hex4(held_dipre_s)
            & to_byte_string(" ") & hex4(held_vidpre_s)
            & to_byte_string(" Q ") & hex4(held_data_s(31 downto 16))
            & hex4(held_data_s(15 downto 0))
            & to_byte_string(" R ") & hex4(held_redge_s)
            & to_byte_string(" Z ") & hex4(held_bad_s(0))
            & to_byte_string(" ") & hex4(held_bad_s(1))
            & to_byte_string(" ") & hex4(held_bad_s(2))
            & to_byte_string("" & cr & lf);

  report_gen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if tx_index_s = line_length_c then
        tx_gap_s <= tx_gap_s + 1;
        if tx_gap_s(tx_gap_s'left) = '1' then
          tx_gap_s <= (others => '0');
          tx_index_s <= 0;
          held_s <= timings_s;
          held_lock_s <= timings_valid_s;
          held_hz_s <= resize(tmds_rate_s, held_hz_s'length);
          held_di_s <= di_frame_s;
          held_audio_s <= audio_frame_s;
          held_err_s <= err_frame_s;
          held_seen_s <= seen_frame_s;
          held_video_s <= video_hold_s;
          held_island_s <= island_hold_s;
          held_vedge_s <= vedge_hold_s;
          held_dedge_s <= dedge_hold_s;
          held_dipre_s <= dipre_hold_s;
          held_vidpre_s <= vidpre_hold_s;
          held_samples_s <= samples_frame_s;
          held_ticks_s <= ticks_frame_s;
          held_data_s <= data_hold_s;
          held_redge_s <= redge_hold_s;
          held_bad_s <= lane_bad_hold_s;
          held_align_s <= rx_aligned_s(0) and rx_aligned_s(1) and rx_aligned_s(2);
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

  leds: nsl_sipeed.pmod_8xled.pmod_8xled_driver
    port map(
      pmod_io => j5_io,
      led_i => led_s
      );

  dvi_hpd_o <= hpd_s;
  ready_led_o <= hpd_s;
  done_led_o <= addressed_s;

end arch;
