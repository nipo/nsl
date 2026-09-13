library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_video;
use nsl_data.bytestream.all;
use ieee.math_real.all;

-- EDID, the block a sink hands a source over DDC to say what it is
-- and what it can show.
--
-- A base block is built here from the same mode_t the rest of the
-- library states modes with, so what is advertised and what is
-- accepted cannot drift apart.
--
-- Which link a source speaks is settled here and nowhere else.  A
-- source sends DVI unless it finds a CTA-861 extension block carrying
-- the HDMI vendor block, so a base block on its own asks for DVI and
-- a base block plus that extension asks for HDMI.  Audio follows the
-- same way: it travels in data islands, which only an HDMI link has,
-- so a sink wanting audio has to ask for HDMI first.
package edid is

  constant block_byte_count_c: natural := 128;
  constant descriptor_byte_count_c: natural := 18;

  subtype edid_block_t is byte_string(0 to block_byte_count_c-1);
  subtype descriptor_t is byte_string(0 to descriptor_byte_count_c-1);

  -- Three letters, five bits each, as EDID packs them.
  function manufacturer_id(name: string) return byte_string;

  -- Detailed timing descriptor, the shape a mode takes in an EDID.
  -- Screen size is in millimetres, and is what a source divides by to
  -- work out a pixel density.
  function detailed_timing(mode: nsl_video.mode.mode_t;
                           h_size_mm: natural := 0;
                           v_size_mm: natural := 0) return descriptor_t;

  -- Monitor name, padded the way EDID asks for.
  function monitor_name(name: string) return descriptor_t;

  -- Range limits, which a source holds any timing it invents against.
  function range_limits(v_hz_min, v_hz_max: natural;
                        h_khz_min, h_khz_max: natural;
                        pixel_mhz_max: natural) return descriptor_t;

  -- A descriptor slot holding nothing.
  function unused_descriptor return descriptor_t;

  -- Standard timing identifier, which states a resolution and a rate
  -- but no timings.  This is how modes beyond the ones the descriptor
  -- slots hold get advertised.
  function standard_timing(mode: nsl_video.mode.mode_t) return byte_string;
  -- The two bytes that state no timing at all.
  function unused_standard_timing return byte_string;

  -- A base block advertising several modes.
  --
  -- The first is the preferred one, the mode a source picks unless
  -- told otherwise, and takes the first descriptor slot.  Further
  -- modes take the one slot left over once the range limits and the
  -- monitor name have theirs, and whatever does not fit is
  -- advertised as a standard timing instead -- a resolution and a
  -- rate, with the source left to work the timings out.
  --
  -- Range limits come from the modes themselves, so a source
  -- inventing a timing is held to what is actually on offer.
  function edid_block(modes: nsl_video.mode.mode_vector;
                      manufacturer: string;
                      product_code: natural;
                      serial: natural := 0;
                      week: natural := 0;
                      year: natural := 2026;
                      name: string := "";
                      h_size_mm: natural := 0;
                      v_size_mm: natural := 0) return edid_block_t;

  -- A base block.  The first descriptor states the preferred timing,
  -- which is the mode a source picks unless told otherwise.
  function edid_block(mode: nsl_video.mode.mode_t;
                      manufacturer: string;
                      product_code: natural;
                      serial: natural := 0;
                      week: natural := 0;
                      year: natural := 2026;
                      name: string := "";
                      h_size_mm: natural := 0;
                      v_size_mm: natural := 0) return edid_block_t;

  -- Sum of a block, which EDID asks to be zero.
  function checksum_of(data: byte_string) return byte;

  -- CEA video identification code of a mode, or zero for a mode CEA
  -- does not name.  Over an HDMI link a source picks a mode by VIC,
  -- so a mode without one can only be offered through the base
  -- block.  VESA modes have none.
  function cea_vic(mode: nsl_video.mode.mode_t) return natural;

  -- What a sink states it can be sent.  LPCM is the only format a
  -- source may send unasked, and the only one an audio sample packet
  -- carries directly.
  type audio_rate_t is (AUDIO_RATE_32K, AUDIO_RATE_44K1, AUDIO_RATE_48K,
                        AUDIO_RATE_88K2, AUDIO_RATE_96K,
                        AUDIO_RATE_176K4, AUDIO_RATE_192K);
  type audio_rate_vector is array(natural range <>) of audio_rate_t;

  type audio_depth_t is (AUDIO_DEPTH_16, AUDIO_DEPTH_20, AUDIO_DEPTH_24);
  type audio_depth_vector is array(natural range <>) of audio_depth_t;

  -- What every source can send, so a sink stating this turns none away.
  constant audio_rates_c: audio_rate_vector := (AUDIO_RATE_32K,
                                                AUDIO_RATE_44K1,
                                                AUDIO_RATE_48K);
  constant audio_depths_c: audio_depth_vector := (AUDIO_DEPTH_16,
                                                  AUDIO_DEPTH_20,
                                                  AUDIO_DEPTH_24);

  -- Data blocks a CTA extension is made of.  Each states its kind and
  -- its length in its first byte, so they are simply laid end to end.

  -- The modes on offer, by VIC.  The first is marked native.  Modes
  -- CEA does not name are left out: there is no way to state them
  -- here.
  function cta_video_block(modes: nsl_video.mode.mode_vector) return byte_string;

  -- One LPCM descriptor.  A source holds what it wants to send
  -- against this and resamples if it has to.
  function cta_audio_block(channels: natural;
                           rates: audio_rate_vector := audio_rates_c;
                           depths: audio_depth_vector := audio_depths_c) return byte_string;

  -- Which speakers the channels are meant for.  A source needs this
  -- before it will send more than two channels.
  function cta_speaker_block(channels: natural) return byte_string;

  -- The HDMI vendor block, which is the whole of the HDMI handshake:
  -- a source sends data islands because it finds the HDMI OUI here,
  -- and sends none when it does not.
  --
  -- The physical address is this sink's place in the CEC tree.  A
  -- sink a source plugs straight into is the root, 0.0.0.0.
  function cta_hdmi_block(max_tmds_hz: natural;
                          pa_a: natural := 0;
                          pa_b: natural := 0;
                          pa_c: natural := 0;
                          pa_d: natural := 0) return byte_string;

  -- A CTA-861 extension block, which is what turns a DVI sink into an
  -- HDMI one.
  --
  -- YCbCr is not offered.  A source sends RGB when that is all a sink
  -- takes, which is what the pixel path downstream expects.
  --
  -- Audio is offered when channels is not zero.  Stating it takes
  -- both the basic audio bit and an audio block: a source reads the
  -- bit to know audio is allowed at all, and the block to know what
  -- to send.
  function cta_extension(modes: nsl_video.mode.mode_vector;
                         audio_channels: natural := 0;
                         audio_rates: audio_rate_vector := audio_rates_c;
                         audio_depths: audio_depth_vector := audio_depths_c;
                         pa_a: natural := 0;
                         pa_b: natural := 0;
                         pa_c: natural := 0;
                         pa_d: natural := 0) return edid_block_t;

  -- What a sink hands over DDC, whole.
  --
  -- A DVI sink hands one block.  An HDMI sink hands two, the base
  -- block stating that one follows, and it is the second that makes
  -- the link an HDMI one.  Nothing else about the two differs, so the
  -- same modes serve either.
  function edid_data(modes: nsl_video.mode.mode_vector;
                     manufacturer: string;
                     product_code: natural;
                     serial: natural := 0;
                     week: natural := 0;
                     year: natural := 2026;
                     name: string := "";
                     h_size_mm: natural := 0;
                     v_size_mm: natural := 0;
                     hdmi: boolean := false;
                     audio_channels: natural := 0;
                     audio_rates: audio_rate_vector := audio_rates_c;
                     audio_depths: audio_depth_vector := audio_depths_c) return byte_string;

end package edid;

package body edid is

  use nsl_video.mode.all;

  function manufacturer_id(name: string) return byte_string
  is
    alias n: string(1 to name'length) is name;
    variable packed: unsigned(15 downto 0) := (others => '0');
    variable letter: natural;
  begin
    assert n'length = 3
      report "An EDID manufacturer is three letters"
      severity failure;

    for i in 1 to 3
    loop
      letter := character'pos(n(i)) - character'pos('A') + 1;
      packed(14 - (i-1)*5 downto 10 - (i-1)*5) := to_unsigned(letter, 5);
    end loop;

    -- Big endian, unlike everything else in an EDID
    return to_byte(to_integer(packed(15 downto 8)))
      & to_byte(to_integer(packed(7 downto 0)));
  end function;

  function detailed_timing(mode: nsl_video.mode.mode_t;
                           h_size_mm: natural := 0;
                           v_size_mm: natural := 0) return descriptor_t
  is
    -- Pixel clock goes in units of ten kilohertz.
    constant clock_c: natural := (pixel_clock_hz(mode) + 5000) / 10000;
    constant h_act_c: natural := mode.h.active;
    constant h_blank_c: natural := mode.h.blank;
    constant v_act_c: natural := mode.v.active;
    constant v_blank_c: natural := mode.v.blank;
    constant h_off_c: natural := mode.h.off;
    constant h_width_c: natural := mode.h.width;
    constant v_off_c: natural := mode.v.off;
    constant v_width_c: natural := mode.v.width;
    variable ret: descriptor_t;
    variable flags: natural;
  begin
    assert clock_c < 65536
      report "Pixel clock does not fit an EDID detailed timing"
      severity failure;

    ret(0) := to_byte(clock_c mod 256);
    ret(1) := to_byte(clock_c / 256);

    ret(2) := to_byte(h_act_c mod 256);
    ret(3) := to_byte(h_blank_c mod 256);
    ret(4) := to_byte((h_act_c / 256) * 16 + (h_blank_c / 256));

    ret(5) := to_byte(v_act_c mod 256);
    ret(6) := to_byte(v_blank_c mod 256);
    ret(7) := to_byte((v_act_c / 256) * 16 + (v_blank_c / 256));

    ret(8) := to_byte(h_off_c mod 256);
    ret(9) := to_byte(h_width_c mod 256);
    ret(10) := to_byte((v_off_c mod 16) * 16 + (v_width_c mod 16));
    ret(11) := to_byte((h_off_c / 256) * 64
                       + (h_width_c / 256) * 16
                       + (v_off_c / 16) * 4
                       + (v_width_c / 16));

    ret(12) := to_byte(h_size_mm mod 256);
    ret(13) := to_byte(v_size_mm mod 256);
    ret(14) := to_byte((h_size_mm / 256) * 16 + (v_size_mm / 256));

    -- No border
    ret(15) := x"00";
    ret(16) := x"00";

    -- Digital separate sync, and the polarities the mode states
    flags := 16#18#;
    if mode.v.sync = '1' then
      flags := flags + 4;
    end if;
    if mode.h.sync = '1' then
      flags := flags + 2;
    end if;
    ret(17) := to_byte(flags);

    return ret;
  end function;

  -- A descriptor that is not a timing starts with a zero pixel clock,
  -- which is what tells the two apart, then states its kind.
  function text_descriptor(kind: byte; text: string) return descriptor_t
  is
    alias t: string(1 to text'length) is text;
    -- What a descriptor holds once its five header bytes are in
    constant length_c: natural := 13;
    variable ret: descriptor_t;
    variable count: natural;
  begin
    ret := (others => x"20");
    ret(0) := x"00";
    ret(1) := x"00";
    ret(2) := x"00";
    ret(3) := kind;
    ret(4) := x"00";

    count := t'length;
    if count > length_c then
      count := length_c;
    end if;

    for i in 1 to count
    loop
      ret(4 + i) := to_byte(character'pos(t(i)));
    end loop;

    -- Anything short of the slot ends with a newline, then spaces
    if count < length_c then
      ret(5 + count) := to_byte(16#0a#);
    end if;

    return ret;
  end function;

  function monitor_name(name: string) return descriptor_t
  is
  begin
    return text_descriptor(x"fc", name);
  end function;

  function range_limits(v_hz_min, v_hz_max: natural;
                        h_khz_min, h_khz_max: natural;
                        pixel_mhz_max: natural) return descriptor_t
  is
    variable ret: descriptor_t;
  begin
    ret := (others => x"00");
    ret(3) := x"fd";
    ret(5) := to_byte(v_hz_min);
    ret(6) := to_byte(v_hz_max);
    ret(7) := to_byte(h_khz_min);
    ret(8) := to_byte(h_khz_max);
    ret(9) := to_byte((pixel_mhz_max + 9) / 10);
    -- No secondary timing formula
    ret(10) := x"00";
    ret(11) := to_byte(16#0a#);
    ret(12 to 17) := (others => x"20");

    return ret;
  end function;

  function unused_descriptor return descriptor_t
  is
    variable ret: descriptor_t;
  begin
    ret := (others => x"00");
    ret(3) := x"10";
    return ret;
  end function;

  function checksum_of(data: byte_string) return byte
  is
    variable sum: natural := 0;
  begin
    for i in data'range
    loop
      sum := (sum + to_integer(data(i))) mod 256;
    end loop;

    return to_byte((256 - sum) mod 256);
  end function;

  function standard_timing(mode: nsl_video.mode.mode_t) return byte_string
  is
    constant width_c: natural := mode.h.active;
    constant height_c: natural := mode.v.active;
    variable aspect, rate: natural;
  begin
    assert width_c mod 8 = 0 and width_c / 8 >= 31 and width_c / 8 - 31 < 256
      report "Resolution does not fit a standard timing identifier"
      severity failure;

    -- Aspect is stated rather than the height, so only the four
    -- EDID knows can be advertised this way.
    if width_c * 10 = height_c * 16 then
      aspect := 0;
    elsif width_c * 3 = height_c * 4 then
      aspect := 1;
    elsif width_c * 4 = height_c * 5 then
      aspect := 2;
    elsif width_c * 9 = height_c * 16 then
      aspect := 3;
    else
      aspect := 1;
      assert false
        report "Aspect ratio has no standard timing identifier, stating 4:3"
        severity warning;
    end if;

    rate := natural(round(refresh_rate(mode))) - 60;
    assert rate < 64
      report "Refresh rate does not fit a standard timing identifier"
      severity failure;

    return to_byte(width_c / 8 - 31) & to_byte(aspect * 64 + rate);
  end function;

  function unused_standard_timing return byte_string
  is
  begin
    return byte_string'(x"01", x"01");
  end function;

  function edid_block(modes: nsl_video.mode.mode_vector;
                      manufacturer: string;
                      product_code: natural;
                      serial: natural := 0;
                      week: natural := 0;
                      year: natural := 2026;
                      name: string := "";
                      h_size_mm: natural := 0;
                      v_size_mm: natural := 0) return edid_block_t
  is
    alias m: nsl_video.mode.mode_vector(0 to modes'length-1) is modes;
    variable ret: edid_block_t;
    variable v_min, v_max, h_min, h_max, clock_max: natural;
    variable rate: natural;
    variable placed, standard: natural;
  begin
    assert m'length /= 0
      report "A sink has to advertise at least one mode"
      severity failure;

    ret := edid_block(mode => m(0),
                      manufacturer => manufacturer,
                      product_code => product_code,
                      serial => serial,
                      week => week,
                      year => year,
                      name => name,
                      h_size_mm => h_size_mm,
                      v_size_mm => v_size_mm);

    -- What every mode on offer needs a source to be able to do
    v_min := 255;
    v_max := 0;
    h_min := 65535;
    h_max := 0;
    clock_max := 0;
    for i in m'range
    loop
      rate := natural(round(refresh_rate(m(i))));
      if rate < v_min then
        v_min := rate;
      end if;
      if rate > v_max then
        v_max := rate;
      end if;
      if h_rate_hz(m(i)) / 1000 < h_min then
        h_min := h_rate_hz(m(i)) / 1000;
      end if;
      if h_rate_hz(m(i)) / 1000 + 1 > h_max then
        h_max := h_rate_hz(m(i)) / 1000 + 1;
      end if;
      if pixel_clock_hz(m(i)) > clock_max then
        clock_max := pixel_clock_hz(m(i));
      end if;
    end loop;

    ret(72 to 89) := range_limits(
      v_hz_min => v_min,
      v_hz_max => v_max,
      h_khz_min => h_min,
      h_khz_max => h_max,
      pixel_mhz_max => (clock_max + 999_999) / 1_000_000);

    -- Of the four descriptor slots, the preferred timing, the range
    -- limits and the name have three, so one is left for a timing.
    placed := 1;
    if m'length > 1 then
      ret(108 to 125) := detailed_timing(m(1), h_size_mm, v_size_mm);
      placed := 2;
    end if;

    -- Whatever is left over is advertised by resolution and rate
    -- alone, which is all a standard timing can say.
    standard := 0;
    for i in placed to m'length-1
    loop
      exit when standard >= 8;
      ret(38 + standard*2 to 39 + standard*2) := standard_timing(m(i));
      standard := standard + 1;
    end loop;

    ret(127) := checksum_of(ret(0 to 126));

    return ret;
  end function;

  function edid_block(mode: nsl_video.mode.mode_t;
                      manufacturer: string;
                      product_code: natural;
                      serial: natural := 0;
                      week: natural := 0;
                      year: natural := 2026;
                      name: string := "";
                      h_size_mm: natural := 0;
                      v_size_mm: natural := 0) return edid_block_t
  is
    variable ret: edid_block_t;
  begin
    ret := (others => x"00");

    -- Header, which is what a source looks for to know it read
    -- anything at all
    ret(0) := x"00";
    ret(1 to 6) := (others => x"ff");
    ret(7) := x"00";

    ret(8 to 9) := manufacturer_id(manufacturer);
    ret(10) := to_byte(product_code mod 256);
    ret(11) := to_byte(product_code / 256);
    ret(12) := to_byte(serial mod 256);
    ret(13) := to_byte((serial / 256) mod 256);
    ret(14) := to_byte((serial / 65536) mod 256);
    ret(15) := to_byte(serial / 16777216);
    ret(16) := to_byte(week);
    ret(17) := to_byte(year - 1990);

    -- EDID 1.3
    ret(18) := x"01";
    ret(19) := x"03";

    -- Digital input.  A 1.3 block says no more than that, which is
    -- all a DVI sink has to say.
    ret(20) := x"80";
    ret(21) := to_byte((h_size_mm + 5) / 10);
    ret(22) := to_byte((v_size_mm + 5) / 10);
    -- Gamma 2.2
    ret(23) := to_byte(120);
    -- RGB 4:4:4, and the first descriptor is the preferred timing
    ret(24) := to_byte(16#0a#);

    -- Chromaticity, sRGB
    ret(25) := x"ee";
    ret(26) := x"91";
    ret(27) := x"a3";
    ret(28) := x"54";
    ret(29) := x"4c";
    ret(30) := x"99";
    ret(31) := x"26";
    ret(32) := x"0f";
    ret(33) := x"50";
    ret(34) := x"54";

    -- Established timings: 640x480 at 60, which every source can send
    -- and which is what one falls back to
    ret(35) := x"20";
    ret(36) := x"00";
    ret(37) := x"00";

    -- Standard timings, none stated
    for i in 0 to 7
    loop
      ret(38 + i*2) := x"01";
      ret(39 + i*2) := x"01";
    end loop;

    ret(54 to 71) := detailed_timing(mode, h_size_mm, v_size_mm);
    ret(72 to 89) := range_limits(
      v_hz_min => 50,
      v_hz_max => 61,
      h_khz_min => 15,
      h_khz_max => 100,
      pixel_mhz_max => (pixel_clock_hz(mode) + 999_999) / 1_000_000);
    ret(90 to 107) := monitor_name(name);
    ret(108 to 125) := unused_descriptor;

    -- No extension block, which is what says this is a DVI sink
    ret(126) := x"00";
    ret(127) := checksum_of(ret(0 to 126));

    return ret;
  end function;


  -- Timings alone say which mode this is.  The nominal frame rate
  -- does not take part: it is a name, and two modes of the same
  -- timings carry the same VIC whatever they are called.
  function same_timings(a, b: nsl_video.mode.mode_t) return boolean
  is
  begin
    return a.h.active = b.h.active and a.h.blank = b.h.blank
      and a.h.off = b.h.off and a.h.width = b.h.width
      and a.v.active = b.v.active and a.v.blank = b.v.blank
      and a.v.off = b.v.off and a.v.width = b.v.width
      and a.pixel_hz = b.pixel_hz;
  end function;

  function cea_vic(mode: nsl_video.mode.mode_t) return natural
  is
  begin
    if same_timings(mode, mode_std_640x480p60_c)
      or same_timings(mode, mode_std_640x480p5994_c) then
      return 1;
    elsif same_timings(mode, mode_std_720x480p5994_c) then
      return 2;
    elsif same_timings(mode, mode_std_1280x720p60_c) then
      return 4;
    elsif same_timings(mode, mode_std_1920x1080p60_c) then
      return 16;
    elsif same_timings(mode, mode_std_720x576p50_c) then
      return 17;
    elsif same_timings(mode, mode_std_1280x720p50_c) then
      return 19;
    elsif same_timings(mode, mode_std_1920x1080p50_c) then
      return 31;
    elsif same_timings(mode, mode_std_1920x1080p30_c) then
      return 34;
    end if;

    -- A VESA mode, or one nobody named
    return 0;
  end function;

  -- First byte of a data block: what it is, and how much follows.
  function cta_block_header(tag, length: natural) return byte
  is
  begin
    assert length < 32
      report "A CTA data block holds at most 31 bytes"
      severity failure;

    return to_byte(tag * 32 + length);
  end function;

  function cta_video_block(modes: nsl_video.mode.mode_vector) return byte_string
  is
    alias m: nsl_video.mode.mode_vector(0 to modes'length-1) is modes;
    variable vics: byte_string(0 to 30);
    variable count: natural := 0;
    variable vic: natural;
  begin
    vics := (others => x"00");

    for i in m'range
    loop
      vic := cea_vic(m(i));
      next when vic = 0;
      exit when count = 31;

      -- The first mode on offer is the one this sink is built around
      if count = 0 then
        vics(count) := to_byte(vic + 128);
      else
        vics(count) := to_byte(vic);
      end if;
      count := count + 1;
    end loop;

    assert count /= 0
      report "No mode on offer has a VIC, so an HDMI source is told of none"
      severity warning;

    return cta_block_header(2, count) & vics(0 to count-1);
  end function;

  function cta_audio_block(channels: natural;
                           rates: audio_rate_vector := audio_rates_c;
                           depths: audio_depth_vector := audio_depths_c) return byte_string
  is
    variable rate_mask, depth_mask: natural := 0;
  begin
    assert channels >= 1 and channels <= 8
      report "An LPCM descriptor states one to eight channels"
      severity failure;

    for i in rates'range
    loop
      rate_mask := rate_mask + 2 ** audio_rate_t'pos(rates(i));
    end loop;

    for i in depths'range
    loop
      depth_mask := depth_mask + 2 ** audio_depth_t'pos(depths(i));
    end loop;

    -- One descriptor of three bytes.  Format one is LPCM, and the
    -- third byte is depths only because the format is LPCM: another
    -- format puts a bit rate there.
    return byte_string'(0 => cta_block_header(1, 3))
      & to_byte(8 + channels - 1)
      & to_byte(rate_mask)
      & to_byte(depth_mask);
  end function;

  function cta_speaker_block(channels: natural) return byte_string
  is
    variable mask: natural;
  begin
    case channels is
      when 2 => mask := 16#01#;
      when 6 => mask := 16#0f#;
      when 8 => mask := 16#4f#;
      when others =>
        mask := 16#01#;
        assert false
          report "No speaker layout is known for this channel count, stating stereo"
          severity warning;
    end case;

    return byte_string'(0 => cta_block_header(4, 3))
      & to_byte(mask) & x"00" & x"00";
  end function;

  function cta_hdmi_block(max_tmds_hz: natural;
                          pa_a: natural := 0;
                          pa_b: natural := 0;
                          pa_c: natural := 0;
                          pa_d: natural := 0) return byte_string
  is
    -- Stated in units of five megahertz, rounded up so a source is
    -- never told it may send faster than this sink can follow.
    constant tmds_c: natural := (max_tmds_hz + 4_999_999) / 5_000_000;
  begin
    assert tmds_c < 256
      report "Maximum TMDS clock does not fit an HDMI vendor block"
      severity failure;

    return byte_string'(0 => cta_block_header(3, 7))
      -- The OUI that means HDMI, least significant byte first
      & x"03" & x"0c" & x"00"
      & to_byte(pa_a * 16 + pa_b)
      & to_byte(pa_c * 16 + pa_d)
      -- No deep colour, no dual link, no ACP or ISRC
      & x"00"
      & to_byte(tmds_c);
  end function;

  -- The fastest mode on offer, which is what a source is told not to
  -- go beyond.
  function max_pixel_clock(modes: nsl_video.mode.mode_vector) return natural
  is
    variable ret: natural := 0;
  begin
    for i in modes'range
    loop
      if pixel_clock_hz(modes(i)) > ret then
        ret := pixel_clock_hz(modes(i));
      end if;
    end loop;

    return ret;
  end function;

  -- The data blocks of an extension, laid end to end.  Audio takes
  -- two of them and a sink offering none states neither.
  function cta_blocks(modes: nsl_video.mode.mode_vector;
                      audio_channels: natural;
                      audio_rates: audio_rate_vector;
                      audio_depths: audio_depth_vector;
                      pa_a, pa_b, pa_c, pa_d: natural) return byte_string
  is
    constant head_c: byte_string
      := cta_hdmi_block(max_pixel_clock(modes), pa_a, pa_b, pa_c, pa_d)
      & cta_video_block(modes);
  begin
    if audio_channels = 0 then
      return head_c;
    end if;

    return head_c
      & cta_audio_block(audio_channels, audio_rates, audio_depths)
      & cta_speaker_block(audio_channels);
  end function;

  function cta_extension(modes: nsl_video.mode.mode_vector;
                         audio_channels: natural := 0;
                         audio_rates: audio_rate_vector := audio_rates_c;
                         audio_depths: audio_depth_vector := audio_depths_c;
                         pa_a: natural := 0;
                         pa_b: natural := 0;
                         pa_c: natural := 0;
                         pa_d: natural := 0) return edid_block_t
  is
    constant blocks_c: byte_string := cta_blocks(
      modes, audio_channels, audio_rates, audio_depths,
      pa_a, pa_b, pa_c, pa_d);
    -- Where the timing descriptors would start.  There are none: the
    -- modes are stated by VIC, and the preferred timing is in the base
    -- block where a source looks for it.
    constant end_c: natural := 4 + blocks_c'length;
    variable ret: edid_block_t;
    variable flags: natural;
  begin
    assert end_c <= 127
      report "CTA data blocks do not fit an extension block"
      severity failure;

    ret := (others => x"00");

    -- A CTA extension, revision three
    ret(0) := x"02";
    ret(1) := x"03";
    ret(2) := to_byte(end_c);

    -- Underscan, so a source sends the pixels it is asked for rather
    -- than a picture with margins around it.  No YCbCr, so it sends
    -- RGB.  No native timing descriptor, there being none here.
    flags := 16#80#;
    if audio_channels /= 0 then
      flags := flags + 16#40#;
    end if;
    ret(3) := to_byte(flags);

    ret(4 to end_c - 1) := blocks_c;

    ret(127) := checksum_of(ret(0 to 126));

    return ret;
  end function;

  -- A base block cannot be built until the blocks following it are
  -- known, so it is told afterwards and its sum redone.
  function with_extensions(blk: edid_block_t; count: natural) return edid_block_t
  is
    variable ret: edid_block_t := blk;
  begin
    ret(126) := to_byte(count);
    ret(127) := checksum_of(ret(0 to 126));
    return ret;
  end function;

  function edid_data(modes: nsl_video.mode.mode_vector;
                     manufacturer: string;
                     product_code: natural;
                     serial: natural := 0;
                     week: natural := 0;
                     year: natural := 2026;
                     name: string := "";
                     h_size_mm: natural := 0;
                     v_size_mm: natural := 0;
                     hdmi: boolean := false;
                     audio_channels: natural := 0;
                     audio_rates: audio_rate_vector := audio_rates_c;
                     audio_depths: audio_depth_vector := audio_depths_c) return byte_string
  is
    constant base_c: edid_block_t := edid_block(
      modes => modes,
      manufacturer => manufacturer,
      product_code => product_code,
      serial => serial,
      week => week,
      year => year,
      name => name,
      h_size_mm => h_size_mm,
      v_size_mm => v_size_mm);
  begin
    assert hdmi or audio_channels = 0
      report "Audio is carried in data islands, which only an HDMI link has"
      severity failure;

    if not hdmi then
      return base_c;
    end if;

    return with_extensions(base_c, 1)
      & cta_extension(modes => modes,
                      audio_channels => audio_channels,
                      audio_rates => audio_rates,
                      audio_depths => audio_depths);
  end function;

end package body edid;
