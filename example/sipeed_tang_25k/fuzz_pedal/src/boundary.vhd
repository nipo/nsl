library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_amba, nsl_audio, nsl_clocking, nsl_color, nsl_data, nsl_digilent,
  nsl_hwdep, nsl_i2s, nsl_icesugar, nsl_indication, nsl_logic, nsl_math,
  nsl_sipeed, nsl_uart, nsl_usb, nsl_video;
use nsl_audio.effect.all;
use nsl_logic.bool.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_math.fixed.all;
use nsl_video.terminal.all;

-- A fuzz box.
--
-- A guitar goes into the line input of the converter on J4 and comes
-- back out of its line output, by way of four blocks which are what
-- a fuzz pedal is made of:
--
--   amplifier -> saturator -> amplifier -> tone control -> amplifier
--
-- The first amplifier is the drive knob.  It does not make anything
-- louder in the end: the saturator after it hands back the same full
-- scale however hard it is driven, so what the knob decides is how
-- far past the threshold the signal goes, and therefore how much of
-- the waveform is flattened rather than how loud what comes out is.
-- Nothing downstream has to undo it for that to hold.
--
-- The saturator's threshold never moves.  A curve that moved would
-- be a new table for every setting, where a fixed one with an
-- amplifier each side is two multipliers.
--
-- The second amplifier is the recovery gain of the output stage, a
-- constant, and the third is the player's volume.  The panel states
-- the two of them together, that being what reads as volume.
--
-- The tone control is a lowpass and a highpass of fixed corners with
-- a knob fading between them, which is the tone stack of the pedals
-- this imitates: the middle of its travel is scooped rather than
-- flat.
--
-- Three knobs, then, and there are two ways to work them.  The four
-- keys of the pad on J6 always work: two choose which knob, two turn
-- it.  A control surface on the USB port -- one particular one, by
-- vendor and product -- turns all three at once instead, a knob
-- each, and needs no choosing.  Either may be used without the
-- other, and using one does not stop the other working.
--
-- The panel on J5 says where the knobs stand, shows how loud the
-- guitar is and how far into the saturator it is being driven, and
-- says what is on the USB port.
--
-- The USB host takes either a low or a full speed device, working
-- out which from the line the device pulls up, and wants a 48 MHz
-- clock of its own, so there are two domains here.  Only reports cross between
-- them, through a FIFO with a clock at each end, which leaves the
-- audio in one domain from converter to converter.
--
-- Everything runs off the board's own oscillator and nothing outside
-- has a say in the rate.  Fifty megahertz gives a master clock of
-- 12.5 MHz and a frame rate of 48828 Hz, a couple of percent above
-- the nominal forty eight thousand: an exact 48 kHz is unreachable
-- from this crystal, since 50 MHz is a power of two times a power of
-- five and every multiple of 48 kHz has a three in it.  Both
-- converters take their clocks from here, so nothing anywhere has to
-- agree with anything else about what a second is.
entity boundary is
  port (
    clk_i : in std_ulogic;

    -- Everything the panel says, for a listener rather than a looker
    uart_tx_o: out std_ulogic;

    ready_led_o: out std_ulogic;
    done_led_o: out std_ulogic;

    -- Digilent Pmod I2S2, converters both ways
    j4_io: inout nsl_digilent.pmod.pmod_double_t;
    -- MuseLab iCESugar 0.96" LCD
    j5_io: inout nsl_digilent.pmod.pmod_double_t;
    -- Sipeed Pmod BTN 4+4
    j6_io: inout nsl_digilent.pmod.pmod_double_t;

    -- USB-A host port
    usb_p_io: inout std_logic;
    usb_n_io: inout std_logic
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;
  -- What the host engine is clocked at.  A full-speed bit is four of
  -- these cycles and a low-speed one thirty two, which is what lets
  -- one engine talk to either kind of device.
  constant usb_hz_c : natural := 48_000_000;
  constant uart_divisor_c : natural := clk_hz_c / 115200 - 1;

  -- The converters' clocks, all divisions of the one above.  A bit
  -- clock is sixty four to a frame and a master clock is two hundred
  -- and fifty six, which is what the converters count to work out
  -- what rate they are being fed.
  constant sck_div_m1_c : natural := 7;
  constant slot_bits_c : natural := 32;
  constant frame_clocks_c : natural := 2 * (sck_div_m1_c + 1) * 2 * slot_bits_c;
  constant rate_c : natural := clk_hz_c / frame_clocks_c;

  constant sample_bits_c : natural := 24;
  -- Room above full scale for the drive to push into, which is what
  -- the saturator reads as how hard it is being driven.
  constant headroom_bits_c : natural := 8;

  -- What the converters carry: two channels, because that is what an
  -- I2S wire is.  A guitar is one channel, so what comes off the
  -- input is narrowed to the side it is plugged into and what goes to
  -- the output is that one side on both.
  constant stereo_c : nsl_audio.pcm_stream.config_t
    := nsl_i2s.stream.stream_config(sample_bits => sample_bits_c);
  constant mono_c : nsl_audio.pcm_stream.config_t
    := nsl_audio.pcm_stream.config(channels => 1,
                                   sample_bits => sample_bits_c);
  constant driven_c : nsl_audio.pcm_stream.config_t
    := nsl_audio.pcm_stream.config(channels => 1,
                                   sample_bits => sample_bits_c
                                   + headroom_bits_c);

  -- Room for the recovery amplifier to work in.  It gives back a
  -- fixed twenty four decibels on a saturator output that already
  -- reaches full scale, and that has to go somewhere until the volume
  -- knob takes it away again after the tone control.  Going nowhere
  -- would mean clipping against the rail before the tone control ever
  -- saw the signal, which is a worse distortion than the one this box
  -- is for.
  constant makeup_bits_c : natural := 4;
  constant boosted_c : nsl_audio.pcm_stream.config_t
    := nsl_audio.pcm_stream.config(channels => 1,
                                   sample_bits => sample_bits_c
                                   + makeup_bits_c);

  -- Frames are produced and taken at the same rate by construction --
  -- both converters run off the same word clock -- so this never
  -- fills or empties.  What it is for is the offset between the two:
  -- the input hands a frame over at the end of the word clock period
  -- it arrived in, and the output wants one at the beginning.
  constant buffer_depth_c : natural := 4;

  -- Knobs.  Three of them, each a step count rather than a value: a
  -- value is what the tables below turn a step into.
  constant knob_count_c : natural := 3;
  constant knob_steps_c : natural := 33;
  constant knob_drive_c : natural := 0;
  constant knob_tone_c : natural := 1;
  constant knob_level_c : natural := 2;

  -- The control surface this looks for on the USB port.  Anything
  -- else that enumerates is named on the panel and otherwise left
  -- alone: a mouse plugged in by mistake should not move the drive.
  constant knobs_vid_c : unsigned(15 downto 0) := x"1500";
  constant knobs_pid_c : unsigned(15 downto 0) := x"0ec1";

  -- Its input report: three bytes of switch bitmap -- sixteen keys
  -- and the four knob presses -- then one signed byte per knob of
  -- how far it was turned since the last report.  Seven bytes, which
  -- fits the eight a low speed packet carries, so one poll brings a
  -- whole report and nothing has to be pieced together.
  --
  -- Only the first three rotations are read.  The keys, the presses
  -- and the fourth knob are there and are ignored.
  constant usb_report_bytes_c : natural := 7;
  constant usb_rotation_c : natural := 3;
  -- 1024 encoder counts per turn, 32 parameter intervals per turn.
  constant usb_rotation_fraction_bits_c : natural := 5;
  constant knob_unit_c : positive := 2**usb_rotation_fraction_bits_c;
  constant knob_position_max_c : natural := (knob_steps_c-1) * knob_unit_c;

  constant usb_fields_c : nsl_usb.hid_host.field_vector(0 to knob_count_c-1) := (
    knob_drive_c => (byte_offset => usb_rotation_c + 0,
                     bit_offset => 0, width => 8),
    knob_tone_c => (byte_offset => usb_rotation_c + 1,
                    bit_offset => 0, width => 8),
    knob_level_c => (byte_offset => usb_rotation_c + 2,
                     bit_offset => 0, width => 8));

  -- Which key is which.  The pair that walks the rows is named for
  -- where the keys are on the board rather than for where they are in
  -- the list, which are opposite: the one lower down moves further
  -- down.
  constant key_down_c : natural := 1;
  constant key_up_c : natural := 2;
  constant key_less_c : natural := 3;
  constant key_more_c : natural := 4;

  -- A step and a half of a decibel, which is fine enough to be
  -- musical and coarse enough to cross the range in a hold.
  constant step_tenth_db_c : natural := 15;

  -- What the amplifier after the saturator gives back.  It is a
  -- constant and not the drive undone: the saturator hands back the
  -- same full scale however hard it is driven, so there is nothing
  -- about the drive left in its output to compensate for.  This is
  -- the recovery gain of the stage, and the knob after it is the
  -- player's volume.
  constant makeup_tenth_db_c : natural := 240;
  -- Where the output knob starts, below unity
  constant level_floor_tenth_db_c : natural := 360;
  -- Six decibels down, which is somewhere to be plugged in at
  constant level_default_c : natural
    := (level_floor_tenth_db_c - 60) / step_tenth_db_c;

  subtype drive_gain_t is ufixed(7 downto -8);
  subtype makeup_gain_t is ufixed(3 downto -18);
  subtype level_gain_t is ufixed(0 downto -22);
  subtype blend_t is ufixed(0 downto -5);

  type drive_gain_vector is array (natural range <>) of drive_gain_t;
  type level_gain_vector is array (natural range <>) of level_gain_t;
  type blend_vector is array (natural range <>) of blend_t;

  -- Nothing to forty eight decibels
  function drive_gains return drive_gain_vector
  is
    variable ret: drive_gain_vector(0 to knob_steps_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_ufixed(10.0 ** (real(i * step_tenth_db_c) / 200.0),
                          drive_gain_t'left, drive_gain_t'right);
    end loop;
    return ret;
  end function;

  -- Thirty six decibels down to twelve up -- of the two amplifiers
  -- together, which is what a player means by volume.  What this one
  -- is actually set to is that less the recovery gain before it, so
  -- the panel states the gain of the output stage rather than the
  -- gain of one amplifier inside it.
  function level_gains return level_gain_vector
  is
    variable ret: level_gain_vector(0 to knob_steps_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_ufixed(
        10.0 ** (real(i * step_tenth_db_c - level_floor_tenth_db_c
                      - makeup_tenth_db_c) / 200.0),
        level_gain_t'left, level_gain_t'right);
    end loop;
    return ret;
  end function;

  -- All lowpass to all highpass
  function blends return blend_vector
  is
    variable ret: blend_vector(0 to knob_steps_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_ufixed(real(i) / real(knob_steps_c-1),
                          blend_t'left, blend_t'right);
    end loop;
    return ret;
  end function;

  -- A number as a character
  function digit(n: natural) return character
  is
  begin
    return character'val(character'pos('0') + (n mod 10));
  end function;

  -- Tenths of a decibel, signed, as five characters
  function decibels(tenths: integer) return string
  is
    variable ret: string(1 to 5);
    variable v: natural;
  begin
    if tenths < 0 then
      ret(1) := '-';
      v := -tenths;
    else
      ret(1) := '+';
      v := tenths;
    end if;

    ret(2) := digit(v / 100);
    ret(3) := digit(v / 10);
    ret(4) := '.';
    ret(5) := digit(v);

    return ret;
  end function;

  -- A percentage as three characters
  function percent(v: natural) return string
  is
    variable ret: string(1 to 3);
  begin
    if v >= 100 then
      ret := "100";
    else
      ret(1) := ' ';
      ret(2) := digit(v / 10);
      ret(3) := digit(v);
    end if;
    return ret;
  end function;

  -- What a step of each knob says on the panel.  A decimal is deep
  -- logic for what never takes more than a few dozen values, so the
  -- few dozen are worked out at elaboration and a step picks one.
  type knob_text_vector is array (natural range <>) of string(1 to 5);
  type percent_text_vector is array (natural range <>) of string(1 to 3);

  function drive_texts return knob_text_vector
  is
    variable ret: knob_text_vector(0 to knob_steps_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := decibels(i * step_tenth_db_c);
    end loop;
    return ret;
  end function;

  function level_texts return knob_text_vector
  is
    variable ret: knob_text_vector(0 to knob_steps_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := decibels(i * step_tenth_db_c - level_floor_tenth_db_c);
    end loop;
    return ret;
  end function;

  function tone_texts return percent_text_vector
  is
    variable ret: percent_text_vector(0 to knob_steps_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := percent(i * 100 / (knob_steps_c-1));
    end loop;
    return ret;
  end function;

  constant drive_text_c : knob_text_vector(0 to knob_steps_c-1) := drive_texts;
  constant level_text_c : knob_text_vector(0 to knob_steps_c-1) := level_texts;
  constant tone_text_c : percent_text_vector(0 to knob_steps_c-1) := tone_texts;

  constant drive_gain_c : drive_gain_vector(0 to knob_steps_c-1) := drive_gains;
  constant makeup_gain_c : makeup_gain_t
    := to_ufixed(10.0 ** (real(makeup_tenth_db_c) / 200.0),
                 makeup_gain_t'left, makeup_gain_t'right);
  constant level_gain_c : level_gain_vector(0 to knob_steps_c-1) := level_gains;
  constant blend_c : blend_vector(0 to knob_steps_c-1) := blends;

  type knob_vector is array (natural range <>) of natural range 0 to knob_steps_c-1;
  type knob_position_vector is array (natural range <>) of natural range 0 to knob_position_max_c;

  -- Panel: a 160x80 panel with a 6x8 font is twenty six columns and
  -- ten rows, of which eight are used.
  constant panel_columns_c : natural := 26;
  constant panel_rows_c : natural := 10;
  -- Six decibels a character, so what is shown is seventy two of them
  constant in_meter_width_c : natural := 12;
  -- The same, counted from full scale up: this one says how far past
  -- it the drive is pushing
  constant drive_meter_width_c : natural := 8;

  -- This is a small backlit panel in a room, not a monitor: a row of
  -- white on black is bright enough to be the only bright thing on
  -- it, and a white background is more light than a line of text has
  -- any business giving off.  So the ground stays black throughout
  -- and what marks the row the keys are turning is that it is white
  -- while the others are not.
  constant palette_c : rgb24_vector(0 to 7) := (
    0 => rgb24_black,
    1 => rgb24_steel_blue,
    2 => rgb24_white,
    3 => rgb24_light_steel_blue,
    4 => rgb24_medium_sea_green,
    5 => rgb24_orange,
    6 => rgb24_slate_gray,
    7 => rgb24_white);

  -- Colors are places in a port rather than palette entries, which is
  -- what lets the row a knob is on change color without the layout
  -- knowing anything about it.
  constant color_title_c : natural := 0;
  constant color_ground_c : natural := 1;
  constant color_knob_c : natural := 2;
  constant color_in_c : natural := 5;
  constant color_drive_c : natural := 6;
  constant color_note_c : natural := 7;
  constant color_usb_c : natural := 8;

  constant panel_labels_c : label_vector := (
    0 => text_label(0, 0, panel_columns_c, color_title_c, color_ground_c),
    1 => text_label(1, 0, panel_columns_c, color_knob_c, color_ground_c),
    2 => text_label(2, 0, panel_columns_c, color_knob_c+1, color_ground_c),
    3 => text_label(3, 0, panel_columns_c, color_knob_c+2, color_ground_c),
    4 => text_label(4, 0, panel_columns_c, color_in_c, color_ground_c),
    5 => text_label(5, 0, panel_columns_c, color_drive_c, color_ground_c),
    6 => text_label(6, 0, panel_columns_c, color_note_c, color_ground_c),
    7 => text_label(7, 0, panel_columns_c, color_note_c, color_ground_c),
    8 => text_label(8, 0, panel_columns_c, color_usb_c, color_ground_c),
    9 => text_label(9, 0, panel_columns_c, color_note_c, color_ground_c));

  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);

  -- A value as that many hexadecimal digits
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

  -- A flag as one character
  function yes(v: std_ulogic) return string
  is
  begin
    if v = '1' then
      return "1";
    end if;
    return "0";
  end function;

  -- Which speed the host decided it was talking to
  function speed_of(v: std_ulogic) return string
  is
  begin
    if v = '1' then
      return "FS";
    end if;
    return "LS";
  end function;

  -- A row padded to the width its label states
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

  -- Where a magnitude sits, six decibels a character.  The highest
  -- bit set is the whole of it: one bit is one doubling, and only the
  -- top of the range is drawn, so what a bar shows is the six times
  -- width decibels below the top of what it is measuring.
  function meter_level(v: unsigned; width: natural) return natural
  is
    alias a: unsigned(v'length-1 downto 0) is v;
    variable top, floor_v: natural;
  begin
    top := 0;

    for i in 0 to a'left
    loop
      if a(i) = '1' then
        top := i + 1;
      end if;
    end loop;

    floor_v := a'length - width;

    if top <= floor_v then
      return 0;
    end if;

    return top - floor_v;
  end function;

  -- That many characters of bar, the rest of the width left showing
  function bar(level, width: natural) return string
  is
    variable ret: string(1 to width) := (others => '.');
  begin
    for i in 1 to width
    loop
      exit when i > level;
      ret(i) := '#';
    end loop;
    return ret;
  end function;

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;

  signal mclk_s : std_ulogic;
  signal mclk_half_s : std_ulogic;

  signal rx_valid_s, rx_channel_s : std_ulogic;
  signal rx_slot_s : unsigned(slot_bits_c-1 downto 0);
  signal tx_ready_s, tx_channel_s : std_ulogic;
  signal tx_slot_s : unsigned(slot_bits_c-1 downto 0);
  signal tx_sample_s : unsigned(sample_bits_c-1 downto 0);

  signal in_s, mono_s, driven_s, fuzzed_s, boosted_s, toned_s, leveled_s,
    out_s, played_s : nsl_amba.axi4_stream.bus_t;

  signal overflow_s, underflow_s : std_ulogic;
  signal lost_in_s, lost_out_s : unsigned(7 downto 0);

  signal in_peak_s : nsl_audio.meter.peak_vector(0 to 0);
  signal drive_peak_s : nsl_audio.meter.peak_vector(0 to 0);
  signal clipping_s : std_ulogic;

  signal usb_clock_s, usb_reset_n_s, usb_locked_s : std_ulogic;
  signal usb_c_s : nsl_usb.io.usb_io_c;
  signal usb_s_s : nsl_usb.io.usb_io_s;
  signal usb_identity_s : nsl_usb.hid_host.device_identity_t;
  signal usb_status_s : nsl_usb.hid_host.hid_host_status_t;
  signal usb_matched_s, usb_enumerated_s, usb_fs_s : std_ulogic;
  signal usb_report_s, report_s : nsl_amba.axi4_stream.bus_t;
  signal usb_values_s :
    std_ulogic_vector(nsl_usb.hid_host.fields_width(usb_fields_c)-1 downto 0);
  signal usb_valid_s : std_ulogic;
  -- The two flags and the identity, in the audio domain
  signal knobs_present_s, device_present_s : std_ulogic;
  signal usb_seen_s : std_ulogic_vector(31 downto 0);
  signal usb_pid_s : std_ulogic_vector(7 downto 0);
  signal usb_control_s : std_ulogic_vector(31 downto 0);
  signal report_pending_s, report_last_s : byte_string(0 to usb_report_bytes_c-1);
  signal report_index_s : natural range 0 to usb_report_bytes_c;
  signal report_count_s : unsigned(15 downto 0);
  -- The two lines as they stand, the clock's lock, the speed that was
  -- read off them, and how many times the engine gave up and started
  -- again: between them these say which of the several ways of seeing
  -- nothing is happening.
  signal usb_probe_s, usb_seen_probe_s : std_ulogic_vector(3 downto 0);
  signal usb_error_count_s, usb_errors_s : unsigned(11 downto 0);
  signal usb_pc_s : std_ulogic_vector(10 downto 0);
  signal usb_packet_count_s, usb_packets_s : unsigned(11 downto 0);

  signal key_s, key_pulse_s : std_ulogic_vector(1 to 4);

  signal knob_s : knob_vector(0 to knob_count_c-1);
  signal knob_position_s : knob_position_vector(0 to knob_count_c-1);
  signal selected_s : natural range 0 to knob_count_c-1;

  signal drive_gain_s : drive_gain_t;
  signal level_gain_s : level_gain_t;
  signal blend_s : blend_t;

  signal second_s : natural range 0 to clk_hz_c-1;
  signal frames_s, rate_s : unsigned(19 downto 0);

  -- Every number on the panel is worked out here and kept, so that
  -- what the label generator picks characters out of is a register
  -- rather than a divider.  Formatting a decimal is deep logic, the
  -- screen is scanned every pixel, and the two of them end to end is
  -- what decides this design's clock rate otherwise.
  signal drive_text_s, level_text_s, rate_text_s : string(1 to 5);
  signal tone_text_s, lost_in_text_s, lost_out_text_s : string(1 to 3);
  signal usb_text_s : string(1 to 9);
  -- What the port looks like when nothing has enumerated, which is
  -- the only time the question comes up.
  signal usb_state_s : string(1 to 25);
  signal in_bar_s : string(1 to in_meter_width_c);
  signal drive_bar_s : string(1 to drive_meter_width_c);

  -- The state row and the identity row, end to end, sent again every
  -- so often.  The panel is the same text; this is so it can be read
  -- without looking at it.
  constant line_length_c : natural := 4 + 9 + 1 + 25 + 15 + 10 + 30 + 2;
  -- What the line says now, and the copy being shifted out.  A line
  -- takes some milliseconds to send and every field in it is moving,
  -- so sending it straight would take each character from a different
  -- instant and show a state that never existed.
  signal line_now_s, line_s : byte_string(0 to line_length_c-1);
  signal uart_index_s : natural range 0 to line_length_c;
  signal uart_gap_s : unsigned(22 downto 0);
  signal uart_ready_s, uart_valid_s : std_ulogic;

  signal panel_s : nsl_video.pixel_stream.bus_t;
  signal panel_synced_s : std_ulogic;
  signal panel_text_s : string(1 to panel_rows_c * panel_columns_c);
  signal panel_color_s : label_color_vector(0 to 8);

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

  -- The host engine wants forty eight megahertz and the rest of this
  -- wants fifty, so the USB side gets a domain of its own.
  usb_pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clk_hz_c,
      output_hz_c => usb_hz_c
      )
    port map(
      clock_i => clock_s,
      clock_o => usb_clock_s,
      reset_n_i => '1',
      locked_o => usb_locked_s
      );

  usb_resync: nsl_clocking.async.async_edge
    port map(
      clock_i => usb_clock_s,
      data_i => usb_locked_s,
      data_o => usb_reset_n_s
      );

  -- The master clock is a quarter of the main one, which puts it at
  -- two hundred and fifty six times the frame rate the bit clock
  -- divider below makes.  Both converters are given this one clock,
  -- so they agree with each other by construction.
  master_clock: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      mclk_half_s <= not mclk_half_s;
      if mclk_half_s = '1' then
        mclk_s <= not mclk_s;
      end if;
    end if;

    if reset_n_s = '0' then
      mclk_half_s <= '0';
      mclk_s <= '0';
    end if;
  end process;

  converters: nsl_digilent.pmod_i2s2.pmod_i2s2_driver
    generic map(
      -- The jumpers are where they left the factory: the input
      -- converter takes the word and bit clocks we send it.
      line_in_slave_c => false
      )
    port map(
      pmod_io => j4_io,

      clock_i => clock_s,
      reset_n_i => reset_n_s,

      rx_mclk_i => mclk_s,
      rx_sck_div_m1_i => to_unsigned(sck_div_m1_c, 4),
      rx_valid_o => rx_valid_s,
      rx_channel_o => rx_channel_s,
      rx_data_o => rx_slot_s,

      tx_mclk_i => mclk_s,
      tx_sck_div_m1_i => to_unsigned(sck_div_m1_c, 4),
      tx_ready_o => tx_ready_s,
      tx_channel_o => tx_channel_s,
      tx_data_i => tx_slot_s
      );

  -- A slot is wider than a sample: the bit clock is sixty four to a
  -- frame because that divides the master clock by four, and a
  -- converter reads the leading twenty four bits of each half and
  -- ignores what follows.
  tx_slot_s <= tx_sample_s & to_unsigned(0, slot_bits_c - sample_bits_c);

  gatherer: nsl_i2s.stream.i2s_stream_receiver
    generic map(
      config_c => stereo_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      valid_i => rx_valid_s,
      channel_i => rx_channel_s,
      data_i => rx_slot_s(slot_bits_c-1 downto slot_bits_c-sample_bits_c),

      out_o => in_s.m,
      out_i => in_s.s,

      overflow_o => overflow_s
      );

  -- A mono instrument in a stereo jack lands on the left, which is
  -- channel zero.
  pick: nsl_audio.routing.pcm_channel_map
    generic map(
      in_config_c => stereo_c,
      out_config_c => mono_c,
      map_c => (0 => 0)
      )
    port map(
      in_i => in_s.m,
      in_o => in_s.s,
      out_o => mono_s.m,
      out_i => mono_s.s
      );

  input_meter: nsl_audio.meter.pcm_peak_meter
    generic map(
      config_c => mono_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      master_i => mono_s.m,
      slave_i => mono_s.s,

      peak_o => in_peak_s
      );

  -- The drive.  Its stream is wider than what came in by the
  -- headroom the saturator's table covers, so nothing is clipped
  -- here: what this decides is how far into the saturator the signal
  -- goes.
  drive: nsl_audio.effect.pcm_gain
    generic map(
      in_config_c => mono_c,
      out_config_c => driven_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => mono_s.m,
      in_o => mono_s.s,

      out_o => driven_s.m,
      out_i => driven_s.s,

      gain_i => drive_gain_s
      );

  -- Measured against the outgoing full scale rather than its own, so
  -- this reads how far past the knee the signal is being pushed.
  drive_meter: nsl_audio.meter.pcm_peak_meter
    generic map(
      config_c => driven_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      master_i => driven_s.m,
      slave_i => driven_s.s,

      peak_o => drive_peak_s
      );

  saturator: nsl_audio.effect.pcm_shaper
    generic map(
      in_config_c => driven_c,
      out_config_c => mono_c,
      -- Clean until it is not, which is what an instrument wants: the
      -- quiet end of a note stays where it was put and the loud end
      -- is flattened.
      shape_c => SHAPE_SOFT_KNEE,
      knee_c => 0.4,
      domain_l2_c => 2,
      table_l2_c => 8
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => driven_s.m,
      in_o => driven_s.s,

      out_o => fuzzed_s.m,
      out_i => fuzzed_s.s
      );

  -- The recovery gain of the output stage, and a constant.  There is
  -- nothing of the drive left in what the saturator hands back -- it
  -- caps at the same place however hard it is pushed -- so there is
  -- nothing about the drive to compensate for here.  What this is for
  -- is keeping the stage's own gain in one place, away from the knob
  -- the player turns.
  makeup: nsl_audio.effect.pcm_gain
    generic map(
      in_config_c => mono_c,
      out_config_c => boosted_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => fuzzed_s.m,
      in_o => fuzzed_s.s,

      out_o => boosted_s.m,
      out_i => boosted_s.s,

      gain_i => makeup_gain_c
      );

  tone: nsl_audio.effect.pcm_tone
    generic map(
      in_config_c => boosted_c,
      out_config_c => boosted_c,
      rate_c => rate_c,
      lowpass_hz_c => 700.0,
      highpass_hz_c => 1500.0
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => boosted_s.m,
      in_o => boosted_s.s,

      out_o => toned_s.m,
      out_i => toned_s.s,

      blend_i => blend_s
      );

  -- Back down to what the converter takes, saturating: this is the
  -- only place in the chain where the rail is a surprise rather than
  -- the point.
  level: nsl_audio.effect.pcm_gain
    generic map(
      in_config_c => boosted_c,
      out_config_c => mono_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => toned_s.m,
      in_o => toned_s.s,

      out_o => leveled_s.m,
      out_i => leveled_s.s,

      gain_i => level_gain_s
      );

  spread: nsl_audio.routing.pcm_channel_map
    generic map(
      in_config_c => mono_c,
      out_config_c => stereo_c,
      map_c => (0 => 0, 1 => 0)
      )
    port map(
      in_i => leveled_s.m,
      in_o => leveled_s.s,
      out_o => out_s.m,
      out_i => out_s.s
      );

  buffering: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => stereo_c.stream,
      depth_c => buffer_depth_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_s,
      reset_n_i => reset_n_s,

      in_i => out_s.m,
      in_o => out_s.s,
      in_free_o => open,

      out_o => played_s.m,
      out_i => played_s.s,
      out_available_o => open
      );

  player: nsl_i2s.stream.i2s_stream_transmitter
    generic map(
      config_c => stereo_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => played_s.m,
      in_o => played_s.s,

      ready_i => tx_ready_s,
      channel_i => tx_channel_s,
      data_o => tx_sample_s,

      underflow_o => underflow_s
      );

  keys: nsl_sipeed.pmod_btn_4_4.pmod_btn_4_4_input
    port map(
      pmod_io => j6_io,

      -- The four slide switches are not used here
      s_o => open,
      k_o => key_s
      );

  repeater: entity work.key_repeater
    generic map(
      clock_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      key_i => key_s,
      pulse_o => key_pulse_s
      );

  host: nsl_usb.hid_host.hid_host_engine
    generic map(
      program_c => nsl_usb.hid_program.hid_program((
        poll_interval_ms => 8,
        report_length => usb_report_bytes_c,
        configuration_value => 1,
        debounce_ms => 200)),
      clock_rate_c => usb_hz_c,
      -- The control surface may come up either way round, and which
      -- it chose is the device's business, not ours.
      full_speed_c => true
      )
    port map(
      reset_n_i => usb_reset_n_s,
      clock_i => usb_clock_s,

      bus_o => usb_c_s,
      bus_i => usb_s_s,

      identity_o => usb_identity_s,
      status_o => usb_status_s,

      report_o => usb_report_s.m,
      report_i => usb_report_s.s
      );

  usb_p_io <= usb_c_s.dp when usb_c_s.oe = '1' else 'Z';
  usb_n_io <= usb_c_s.dm when usb_c_s.oe = '1' else 'Z';
  usb_s_s.dp <= usb_p_io;
  usb_s_s.dm <= usb_n_io;

  usb_enumerated_s <= to_logic(usb_identity_s.valid);
  usb_fs_s <= to_logic(usb_status_s.full_speed);
  usb_matched_s <= to_logic(usb_identity_s.valid
                            and usb_identity_s.vid = knobs_vid_c
                            and usb_identity_s.pid = knobs_pid_c);

  -- Reports cross here and nothing else does.  A whole report is
  -- seven beats and two of them fit, which is more than a poll
  -- interval's worth: the reading side is thirty times faster than
  -- the writing one and never falls behind.
  report_cross: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => nsl_usb.hid_host.report_cfg_c,
      depth_c => 16,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => usb_clock_s,
      clock_i(1) => clock_s,
      reset_n_i => usb_reset_n_s,

      in_i => usb_report_s.m,
      in_o => usb_report_s.s,
      in_free_o => open,

      out_o => report_s.m,
      out_i => report_s.s,
      out_available_o => open
      );

  -- Taking the report apart happens on this side of the crossing, so
  -- what travels is bytes rather than a pile of extracted fields with
  -- a pulse beside them that would have to be carried across too.
  rotations: nsl_usb.hid_host.hid_host_extractor
    generic map(
      fields_c => usb_fields_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      report_i => report_s.m,
      report_o => report_s.s,

      values_o => usb_values_s,
      valid_o => usb_valid_s
      );

  -- The bus itself, straight off the pins.  A device that is plugged
  -- in and powered holds one of the two up whatever else is wrong.
  usb_probe_s <= usb_fs_s & usb_locked_s & usb_n_io & usb_p_io;

  report_debug: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if nsl_amba.axi4_stream.is_valid(nsl_usb.hid_host.report_cfg_c, report_s.m)
        and nsl_amba.axi4_stream.is_ready(nsl_usb.hid_host.report_cfg_c, report_s.s) then
        if report_index_s < usb_report_bytes_c then
          report_pending_s(report_index_s)
            <= nsl_amba.axi4_stream.bytes(nsl_usb.hid_host.report_cfg_c, report_s.m)(0);
          report_index_s <= report_index_s + 1;
        end if;
        if nsl_amba.axi4_stream.is_last(nsl_usb.hid_host.report_cfg_c, report_s.m) then
          report_index_s <= 0;
        end if;
      end if;
      if usb_valid_s = '1' then
        report_last_s <= report_pending_s;
        report_count_s <= report_count_s + 1;
      end if;
    end if;
    if reset_n_s = '0' then
      report_index_s <= 0;
      report_pending_s <= (others => x"00");
      report_last_s <= (others => x"00");
      report_count_s <= (others => '0');
    end if;
  end process;

  line_cross: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => usb_probe_s'length
      )
    port map(
      clock_i => clock_s,
      data_i => usb_probe_s,
      data_o => usb_seen_probe_s
      );

  errors: process(usb_clock_s, usb_reset_n_s) is
  begin
    if rising_edge(usb_clock_s) then
      if usb_status_s.error = '1' then
        usb_error_count_s <= usb_error_count_s + 1;
      end if;

      if usb_status_s.packet = '1' then
        usb_packet_count_s <= usb_packet_count_s + 1;
      end if;
    end if;

    if usb_reset_n_s = '0' then
      usb_error_count_s <= (others => '0');
      usb_packet_count_s <= (others => '0');
    end if;
  end process;

  -- Where the microcode is.  Read as configuration rather than as a
  -- counter: what it is wanted for is an engine that has stopped, and
  -- one that has stopped is not changing it.
  pc_cross: nsl_clocking.interdomain.interdomain_static_reg
    generic map(
      data_width_c => usb_pc_s'length
      )
    port map(
      input_clock_i => usb_clock_s,
      data_i => std_ulogic_vector(usb_status_s.program_counter),
      data_o => usb_pc_s
      );

  packet_cross: nsl_clocking.interdomain.interdomain_counter
    generic map(
      data_width_c => usb_packet_count_s'length
      )
    port map(
      clock_in_i => usb_clock_s,
      clock_out_i => clock_s,
      data_i => usb_packet_count_s,
      data_o => usb_packets_s
      );

  error_cross: nsl_clocking.interdomain.interdomain_counter
    generic map(
      data_width_c => usb_error_count_s'length
      )
    port map(
      clock_in_i => usb_clock_s,
      clock_out_i => clock_s,
      data_i => usb_error_count_s,
      data_o => usb_errors_s
      );

  -- Two flags, each its own bit, so nothing is torn by crossing them
  -- apart from each other.
  flags_cross: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 2
      )
    port map(
      clock_i => clock_s,
      data_i(0) => usb_matched_s,
      data_i(1) => usb_enumerated_s,
      data_o(0) => knobs_present_s,
      data_o(1) => device_present_s
      );

  -- What is on the port, for the panel only.  It settles once a
  -- device has enumerated and does not change again until one is
  -- unplugged, so it is read across the boundary as it stands.
  identity_cross: nsl_clocking.interdomain.interdomain_static_reg
    generic map(
      data_width_c => 32
      )
    port map(
      input_clock_i => usb_clock_s,
      data_i(31 downto 16) => std_ulogic_vector(usb_identity_s.vid),
      data_i(15 downto 0) => std_ulogic_vector(usb_identity_s.pid),
      data_o => usb_seen_s
      );

  pid_cross: nsl_clocking.interdomain.interdomain_static_reg
    generic map(data_width_c => 8)
    port map(
      input_clock_i => usb_clock_s,
      data_i => usb_status_s.received_pid,
      data_o => usb_pid_s
      );

  control_cross: nsl_clocking.interdomain.interdomain_static_reg
    generic map(data_width_c => 32)
    port map(
      input_clock_i => usb_clock_s,
      data_i => usb_status_s.control_debug,
      data_o => usb_control_s
      );

  -- Two keys walk the knobs and two turn the one chosen.  Nothing
  -- wraps round at the ends: a knob that went from all the way up to
  -- all the way down on one press would be a nuisance.
  knobs: process(clock_s, reset_n_s) is
    variable turned: integer;
  begin
    if rising_edge(clock_s) then
      -- A report turns all three at once, by however far each was
      -- moved since the last one, and stops at either end rather than
      -- wrapping round.  It takes precedence over a key pressed in
      -- the same cycle, which is a coincidence nobody will notice.
      if usb_valid_s = '1' and knobs_present_s = '1' then
        for i in 0 to knob_count_c-1
        loop
          turned := knob_position_s(i)
                    + to_integer(signed(usb_values_s(
                      nsl_usb.hid_host.field_offset(usb_fields_c, i) + 7
                      downto nsl_usb.hid_host.field_offset(usb_fields_c, i))));

          if turned < 0 then
            knob_position_s(i) <= 0;
          elsif turned > knob_position_max_c then
            knob_position_s(i) <= knob_position_max_c;
          else
            knob_position_s(i) <= turned;
          end if;
        end loop;
      elsif key_pulse_s(key_up_c) = '1' then
        if selected_s /= 0 then
          selected_s <= selected_s - 1;
        end if;
      elsif key_pulse_s(key_down_c) = '1' then
        if selected_s /= knob_count_c-1 then
          selected_s <= selected_s + 1;
        end if;
      elsif key_pulse_s(key_less_c) = '1' then
        if knob_position_s(selected_s) >= knob_unit_c then
          knob_position_s(selected_s) <= knob_position_s(selected_s) - knob_unit_c;
        else
          knob_position_s(selected_s) <= 0;
        end if;
      elsif key_pulse_s(key_more_c) = '1' then
        if knob_position_s(selected_s) <= knob_position_max_c - knob_unit_c then
          knob_position_s(selected_s) <= knob_position_s(selected_s) + knob_unit_c;
        else
          knob_position_s(selected_s) <= knob_position_max_c;
        end if;
      end if;
    end if;

    if reset_n_s = '0' then
      selected_s <= knob_drive_c;
      -- The drive and the tone in the middle of their travel, and
      -- the volume a little under unity.
      knob_position_s(knob_drive_c) <= (knob_steps_c / 2) * knob_unit_c;
      knob_position_s(knob_tone_c) <= (knob_steps_c / 2) * knob_unit_c;
      knob_position_s(knob_level_c) <= level_default_c * knob_unit_c;
    end if;
  end process;

  knob_values: for i in 0 to knob_count_c-1 generate
    knob_s(i) <= knob_position_s(i) / knob_unit_c;
  end generate;

  drive_gain_s <= drive_gain_c(knob_s(knob_drive_c));
  blend_s <= blend_c(knob_s(knob_tone_c));
  level_gain_s <= level_gain_c(knob_s(knob_level_c));

  -- What the input converter actually delivered over a second, which
  -- is the one number here that says the whole thing is running.
  rates: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if nsl_audio.pcm_stream.is_taken(stereo_c, in_s.m, in_s.s) then
        frames_s <= frames_s + 1;
      end if;

      if second_s = 0 then
        second_s <= clk_hz_c-1;
        rate_s <= frames_s;
        frames_s <= (others => '0');
      else
        second_s <= second_s - 1;
      end if;
    end if;

    if reset_n_s = '0' then
      second_s <= clk_hz_c-1;
      frames_s <= (others => '0');
      rate_s <= (others => '0');
    end if;
  end process;

  -- Frames that went missing either end.  Both should sit still once
  -- the wire has started; one that climbs says the chain cannot keep
  -- up with the converters, which nothing here should ever do.
  losses: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if overflow_s = '1' then
        lost_in_s <= lost_in_s + 1;
      end if;

      if underflow_s = '1' then
        lost_out_s <= lost_out_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      lost_in_s <= (others => '0');
      lost_out_s <= (others => '0');
    end if;
  end process;

  -- Lit while the drive is pushing past what the saturator hands
  -- back, which is the whole point of the thing but is worth being
  -- able to see.
  clipping_s <= '1'
                when drive_peak_s(0)(drive_peak_s(0)'left downto sample_bits_c-1)
                /= (drive_peak_s(0)'left downto sample_bits_c-1 => '0')
                else '0';

  panel_text: nsl_video.terminal.terminal_labels
    generic map(
      row_count_l2_c => 4,
      column_count_l2_c => 5,
      character_count_l2_c => 8,
      color_palette_c => palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => panel_labels_c,
      blank_color_c => color_ground_c,
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

      pmod_io => j5_io
      );

  labels: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      drive_text_s <= drive_text_c(knob_s(knob_drive_c));
      tone_text_s <= tone_text_c(knob_s(knob_tone_c));
      level_text_s <= level_text_c(knob_s(knob_level_c));
      rate_text_s <= to_decimal_string(rate_s, 5);
      lost_in_text_s <= to_decimal_string(lost_in_s, 3);
      lost_out_text_s <= to_decimal_string(lost_out_s, 3);

      usb_state_s <= "DP" & yes(usb_seen_probe_s(0))
                     & " DN" & yes(usb_seen_probe_s(1))
                     & " " & speed_of(usb_seen_probe_s(3))
                     & " E" & hex(usb_errors_s, 3)
                     & " R" & hex(usb_packets_s, 3)
                     & " P" & hex(resize(unsigned(usb_pc_s), 12), 3);

      if device_present_s = '1' then
        usb_text_s <= hex(unsigned(usb_seen_s(31 downto 16)), 4) & ":"
                      & hex(unsigned(usb_seen_s(15 downto 0)), 4);
      else
        usb_text_s <= "SEARCHING";
      end if;

      in_bar_s <= bar(meter_level(in_peak_s(0)(sample_bits_c-1 downto 0),
                                  in_meter_width_c),
                      in_meter_width_c);
      drive_bar_s <= bar(meter_level(
        drive_peak_s(0)(sample_bits_c + headroom_bits_c-1 downto 0),
        drive_meter_width_c),
                         drive_meter_width_c);
    end if;

    if reset_n_s = '0' then
      drive_text_s <= (others => ' ');
      level_text_s <= (others => ' ');
      rate_text_s <= (others => ' ');
      tone_text_s <= (others => ' ');
      lost_in_text_s <= (others => ' ');
      lost_out_text_s <= (others => ' ');
      usb_text_s <= (others => ' ');
      usb_state_s <= (others => ' ');
      in_bar_s <= (others => ' ');
      drive_bar_s <= (others => ' ');
    end if;
  end process;

  -- Nothing but wires: every piece below is either a constant or a
  -- register.
  panel_text_s <= fit("NSL FUZZ PEDAL", panel_columns_c)
                  & fit("DRIVE " & drive_text_s & " dB", panel_columns_c)
                  & fit("TONE  " & tone_text_s & " %", panel_columns_c)
                  & fit("LEVEL " & level_text_s & " dB", panel_columns_c)
                  & fit("IN  " & in_bar_s, panel_columns_c)
                  & fit("DRV " & drive_bar_s, panel_columns_c)
                  & fit("RATE " & rate_text_s & " Hz", panel_columns_c)
                  & fit("IN LOST " & lost_in_text_s
                        & " OUT " & lost_out_text_s, panel_columns_c)
                  & fit("USB " & usb_text_s, panel_columns_c)
                  & fit(usb_state_s, panel_columns_c);

  -- The row the keys are turning is white; the rest are not.
  colors: process(selected_s, knobs_present_s) is
  begin
    panel_color_s(color_title_c) <= to_unsigned(3, 8);
    panel_color_s(color_ground_c) <= to_unsigned(0, 8);
    panel_color_s(color_in_c) <= to_unsigned(4, 8);
    panel_color_s(color_drive_c) <= to_unsigned(5, 8);
    panel_color_s(color_note_c) <= to_unsigned(6, 8);

    -- The device that turns the knobs is shown in the same green as
    -- the input meter; anything else on the port is just noted.
    if knobs_present_s = '1' then
      panel_color_s(color_usb_c) <= to_unsigned(4, 8);
    else
      panel_color_s(color_usb_c) <= to_unsigned(6, 8);
    end if;

    for i in 0 to knob_count_c-1
    loop
      if selected_s = i then
        panel_color_s(color_knob_c + i) <= to_unsigned(2, 8);
      else
        panel_color_s(color_knob_c + i) <= to_unsigned(1, 8);
      end if;
    end loop;
  end process;

  line_now_s <= to_byte_string("USB " & usb_text_s & " " & usb_state_s)
                & to_byte_string(" I" & to_hex_string(usb_seen_s(31 downto 16))
                                 & ":" & to_hex_string(usb_seen_s(15 downto 0))
                                 & " Q" & to_hex_string(usb_pid_s))
                & to_byte_string(" C" & to_hex_string(usb_control_s))
                & to_byte_string(" H" & to_hex_string(std_ulogic_vector(report_count_s))
                                 & " D" & to_hex_string(report_last_s)
                                 & " K" & to_hex_string(std_ulogic_vector(to_unsigned(knob_s(0), 8)))
                                 & to_hex_string(std_ulogic_vector(to_unsigned(knob_s(1), 8)))
                                 & to_hex_string(std_ulogic_vector(to_unsigned(knob_s(2), 8))))
                & to_byte_string("" & cr & lf);

  report_gen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if uart_index_s = line_length_c then
        uart_gap_s <= uart_gap_s + 1;
        if uart_gap_s(uart_gap_s'left) = '1' then
          uart_gap_s <= (others => '0');
          uart_index_s <= 0;
          line_s <= line_now_s;
        end if;
      elsif uart_ready_s = '1' then
        uart_index_s <= uart_index_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      uart_index_s <= line_length_c;
      uart_gap_s <= (others => '0');
      line_s <= (others => x"20");
    end if;
  end process;

  uart_valid_s <= '1' when uart_index_s /= line_length_c else '0';

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
      data_i => std_ulogic_vector(line_s(uart_index_s mod line_length_c)),
      ready_o => uart_ready_s,
      valid_i => uart_valid_s
      );

  ready_led_o <= panel_synced_s;
  done_led_o <= clipping_s;

end arch;
