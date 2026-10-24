library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

library nsl_amba, nsl_color, nsl_data, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

-- This package carries raster pixel data over AXI4-Stream.
--
-- A packet is a line: TLAST marks its last beat, and the first beat
-- of a line is simply the one following a TLAST.  Three TUSER bits
-- carry what a line boundary cannot say by itself:
--
-- - SOF, on the first beat of a frame,
-- - EOF, on the TLAST beat closing the last line of a frame,
-- - ERROR, on the TLAST beat, telling the line is not to be trusted.
--
-- Lines rather than frames because that is the packet size every
-- generic stream block is built for: a FIFO holds one, a DMA
-- descriptor writes one, a scaler works on one.  A frame-sized
-- packet is millions of beats and buys nothing.
--
-- The stream carries active pixels only.  Blanking is a property of
-- the mode, not of pixel data, and shows up here as beats where
-- valid is deasserted.
--
-- A beat holds pixel_count pixels, each holding component_count
-- components of component_bits bits.  Components are byte-aligned in
-- TDATA, least significant byte first, and appear in the order the
-- colorspace names them: an RGB stream sends R, then G, then B.
-- Colorimetry itself is not stated here: a receiver only learns it
-- from metadata that arrives after pixels start, so it travels
-- beside the stream rather than in its type.
--
-- Wire-level signals are plain nsl_amba.axi4_stream master/slave
-- records, so any existing AXI4-Stream component operates on such a
-- stream unchanged. This package only adds a configuration record
-- enforcing the framing and user width relationships, and
-- accessors/constructors expressing beats in terms of pixels.
package pixel_stream is

  subtype master_t is nsl_amba.axi4_stream.master_t;
  subtype slave_t is nsl_amba.axi4_stream.slave_t;
  subtype bus_t is nsl_amba.axi4_stream.bus_t;

  subtype master_vector is nsl_amba.axi4_stream.master_vector;
  subtype slave_vector is nsl_amba.axi4_stream.slave_vector;
  subtype bus_vector is nsl_amba.axi4_stream.bus_vector;

  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');

  -- TUSER bit assignment.
  constant user_sof_c: natural := 0;
  constant user_eof_c: natural := 1;
  constant user_error_c: natural := 2;
  constant user_width_c: natural := 3;

  constant max_component_count_c: natural := 4;
  constant max_component_bits_c: natural := 16;

  -- One color component, right-aligned in the maximum width.
  subtype component_t is unsigned(max_component_bits_c-1 downto 0);
  -- One pixel.  Component 0 is the one the colorspace names first.
  type pixel_t is array (natural range 0 to max_component_count_c-1) of component_t;
  type pixel_vector is array (natural range <>) of pixel_t;

  constant pixel_zero_c: pixel_t := (others => (others => '0'));
  constant pixel_dontcare_c: pixel_t := (others => (others => '-'));

  -- What the components of a pixel stand for.
  --
  -- - INDEXED: one component, an index in a palette that lives
  --   outside of the stream.  Generators emit this, a palette
  --   expander turns it into one of the others.
  -- - RGB: three components, R, G, B.
  -- - YCBCR444: three components, Y, Cb, Cr.  Chroma is offset
  --   binary, half scale is no chroma.
  -- - YCBCR422: two components, Y and a chroma that alternates along
  --   the line: Cb on even pixels, Cr on odd ones, counted from the
  --   first pixel of the line.  Lines have an even pixel count.
  -- - GRAY: one component, luma.  One bit makes black and white.
  -- - RGB565: one 16-bit component packing R in bits 15-11, G in
  --   bits 10-5, B in bits 4-0.  Half the bytes of RGB888, for
  --   storage and links; blocks that work on colors want it unpacked
  --   to RGB first.
  --
  -- AUTO is only an argument value for config(): it resolves from
  -- the component count, one component is INDEXED, others are RGB.
  type colorspace_t is (
    COLORSPACE_AUTO,
    COLORSPACE_INDEXED,
    COLORSPACE_RGB,
    COLORSPACE_YCBCR444,
    COLORSPACE_YCBCR422,
    COLORSPACE_GRAY,
    COLORSPACE_RGB565
    );

  -- Colorimetry of luma and color difference.  It is informative to
  -- the stream itself: it states what the components mean, which is
  -- what a sink reports downstream (e.g. in an HDMI AVI infoframe)
  -- and what constant colors are computed with.
  type colorimetry_t is (
    COLORIMETRY_BT601,
    COLORIMETRY_BT709
    );

  -- Code range a component spans.  FULL spans all codes, LIMITED
  -- spans 16-235 (luma, RGB) and 16-240 (chroma) in eight bits,
  -- scaled for other widths.  AUTO is only an argument value for
  -- config(): it resolves to LIMITED for YCbCr, FULL otherwise.
  type quantization_t is (
    QUANTIZATION_AUTO,
    QUANTIZATION_FULL,
    QUANTIZATION_LIMITED
    );

  -- Pixel layout of a beat, and the AXI4-Stream configuration that
  -- carries it.  The stream configuration is held rather than
  -- derived on use: accessors run in RTL, and deriving there would
  -- put the derivation itself in the logic.
  type config_t is
  record
    stream: nsl_amba.axi4_stream.config_t;
    pixel_count: natural;
    component_count: natural range 1 to max_component_count_c;
    component_bits: natural range 1 to max_component_bits_c;
    colorspace: colorspace_t;
    colorimetry: colorimetry_t;
    quantization: quantization_t;
  end record;

  type config_vector is array (natural range <>) of config_t;

  -- Bytes one component takes in TDATA.
  function component_bytes(cfg: config_t) return natural;
  -- Bytes one pixel takes in TDATA.
  function pixel_bytes(cfg: config_t) return natural;

  -- Underlying AXI4-Stream configuration.  Data width follows the
  -- beat pixel count, user width is fixed by the framing bits, and
  -- last is always present: it is what states a line boundary.
  function as_stream_config(cfg: config_t) return nsl_amba.axi4_stream.config_t;
  -- Whether beats may be held back.
  function has_ready(cfg: config_t) return boolean;

  -- Component count a colorspace takes, zero for AUTO.
  function colorspace_components(colorspace: colorspace_t) return natural;

  -- Components default to what the colorspace takes, and to three
  -- RGB components when neither is stated.  When both are stated,
  -- they must agree.  RGB565 needs component_bits stated as 16.
  function config(
    pixels: natural := 1;
    components: natural range 0 to max_component_count_c := 0;
    component_bits: natural range 1 to max_component_bits_c := 8;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    ready: boolean := true;
    colorspace: colorspace_t := COLORSPACE_AUTO;
    colorimetry: colorimetry_t := COLORIMETRY_BT709;
    quantization: quantization_t := QUANTIZATION_AUTO) return config_t;

  function is_valid(cfg: config_t; m: master_t) return boolean;
  function is_ready(cfg: config_t; s: slave_t) return boolean;
  -- Whether a beat changes hands this cycle.  With is_eof, this is
  -- what a frame boundary looks like from beside the stream.
  function is_taken(cfg: config_t; m: master_t; s: slave_t) return boolean;
  -- Beat closes a line.
  function is_last(cfg: config_t; m: master_t) return boolean;
  -- Beat opens a frame.
  function is_sof(cfg: config_t; m: master_t) return boolean;
  -- Beat closes a frame.  Only meaningful on a beat closing a line.
  function is_eof(cfg: config_t; m: master_t) return boolean;
  -- Line the beat closes is not to be trusted.  Only meaningful on a
  -- beat closing a line.
  function is_error(cfg: config_t; m: master_t) return boolean;

  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  function user(cfg: config_t; m: master_t) return std_ulogic_vector;
  function id(cfg: config_t; m: master_t) return std_ulogic_vector;
  function dest(cfg: config_t; m: master_t) return std_ulogic_vector;

  -- Pixel at a given index of the beat.  Components above
  -- component_count read as zero.
  function pixel(cfg: config_t;
                 m: master_t;
                 index: natural := 0) return pixel_t;
  -- All pixels of the beat, index 0 first.
  function pixels(cfg: config_t; m: master_t) return pixel_vector;

  -- Requires cfg.pixel_count = 1.
  function transfer(cfg: config_t;
                    pixel: pixel_t;
                    keep: boolean := true;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    sof: boolean := false;
                    last: boolean := false;
                    eof: boolean := false;
                    error: boolean := false) return master_t;

  function transfer(cfg: config_t;
                    pixels: pixel_vector;
                    keep: std_ulogic_vector := na_suv;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    sof: boolean := false;
                    last: boolean := false;
                    eof: boolean := false;
                    error: boolean := false) return master_t;

  function transfer_defaults(cfg: config_t) return master_t;

  function accept(cfg: config_t;
                  ready: boolean := false) return slave_t;

  -- RGB conversion, for the usual three-component configuration and
  -- for RGB565.  Components narrower than eight bits are left-aligned
  -- in the rgb24 component, wider ones are truncated.
  function to_pixel(cfg: config_t; color: nsl_color.rgb.rgb24) return pixel_t;
  function to_rgb24(cfg: config_t; p: pixel_t) return nsl_color.rgb.rgb24;

  -- YCbCr conversion for YCBCR444 configurations, component
  -- alignment as for RGB.  Signed chroma of ycbcr24 maps to offset
  -- binary components.  These are code relabelings for use in logic:
  -- values are taken as they are, in the quantization of the
  -- configuration.
  function to_pixel(cfg: config_t; color: nsl_color.ycbcr.ycbcr24) return pixel_t;
  function to_ycbcr24(cfg: config_t; p: pixel_t) return nsl_color.ycbcr.ycbcr24;

  -- A constant color, stated in RGB, as the pixel a configuration
  -- shows it with, following its colorspace, colorimetry and
  -- quantization.  For YCBCR422, the pixel holds Y, Cb, Cr like
  -- YCBCR444 would: a 4:2:2 pixel takes one of the two chroma
  -- components depending on its position, so a color has to state
  -- both.  An INDEXED configuration has no color to show.
  --
  -- This computes on reals: it is meant for constants, not for logic.
  function color(cfg: config_t; c: nsl_color.rgb.rgb24) return pixel_t;

  -- A palette of constant colors, each converted with color().
  function palette(cfg: config_t; colors: nsl_color.rgb.rgb24_vector) return pixel_vector;

end package;

package body pixel_stream is

  function component_bytes(cfg: config_t) return natural
  is
  begin
    return (cfg.component_bits + 7) / 8;
  end function;

  function pixel_bytes(cfg: config_t) return natural
  is
  begin
    return cfg.component_count * component_bytes(cfg);
  end function;

  function as_stream_config(cfg: config_t) return nsl_amba.axi4_stream.config_t
  is
  begin
    return cfg.stream;
  end function;

  function has_ready(cfg: config_t) return boolean
  is
  begin
    return cfg.stream.has_ready;
  end function;

  function colorspace_components(colorspace: colorspace_t) return natural
  is
  begin
    case colorspace is
      when COLORSPACE_AUTO => return 0;
      when COLORSPACE_INDEXED | COLORSPACE_GRAY | COLORSPACE_RGB565 => return 1;
      when COLORSPACE_YCBCR422 => return 2;
      when COLORSPACE_RGB | COLORSPACE_YCBCR444 => return 3;
    end case;
  end function;

  function config(
    pixels: natural := 1;
    components: natural range 0 to max_component_count_c := 0;
    component_bits: natural range 1 to max_component_bits_c := 8;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    ready: boolean := true;
    colorspace: colorspace_t := COLORSPACE_AUTO;
    colorimetry: colorimetry_t := COLORIMETRY_BT709;
    quantization: quantization_t := QUANTIZATION_AUTO) return config_t
  is
    variable components_v: natural range 1 to max_component_count_c;
    variable colorspace_v: colorspace_t;
    variable quantization_v: quantization_t;
    variable pixel_bytes_v: natural;
  begin
    if colorspace /= COLORSPACE_AUTO then
      assert components = 0 or components = colorspace_components(colorspace)
        report "Component count does not match colorspace"
        severity failure;
      assert colorspace /= COLORSPACE_RGB565 or component_bits = 16
        report "RGB565 packs a pixel in one 16-bit component"
        severity failure;
      components_v := colorspace_components(colorspace);
      colorspace_v := colorspace;
    elsif components = 0 then
      components_v := 3;
      colorspace_v := COLORSPACE_RGB;
    elsif components = 1 then
      components_v := 1;
      colorspace_v := COLORSPACE_INDEXED;
    else
      components_v := components;
      colorspace_v := COLORSPACE_RGB;
    end if;

    if quantization /= QUANTIZATION_AUTO then
      quantization_v := quantization;
    elsif colorspace_v = COLORSPACE_YCBCR444 or colorspace_v = COLORSPACE_YCBCR422 then
      quantization_v := QUANTIZATION_LIMITED;
    else
      quantization_v := QUANTIZATION_FULL;
    end if;

    pixel_bytes_v := components_v * ((component_bits + 7) / 8);

    assert pixels * pixel_bytes_v <= nsl_amba.axi4_stream.max_data_width_c
      report "Beat does not fit in maximum stream data width"
      severity failure;

    return config_t'(
      stream => nsl_amba.axi4_stream.config(
        bytes => pixels * pixel_bytes_v,
        user => user_width_c,
        id => id,
        dest => dest,
        keep => keep,
        strobe => false,
        ready => ready,
        last => true),
      pixel_count => pixels,
      component_count => components_v,
      component_bits => component_bits,
      colorspace => colorspace_v,
      colorimetry => colorimetry,
      quantization => quantization_v);
  end function;

  function is_valid(cfg: config_t; m: master_t) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_valid(as_stream_config(cfg), m);
  end function;

  function is_ready(cfg: config_t; s: slave_t) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_ready(as_stream_config(cfg), s);
  end function;

  function is_taken(cfg: config_t; m: master_t; s: slave_t) return boolean
  is
  begin
    return is_valid(cfg, m) and is_ready(cfg, s);
  end function;

  function is_last(cfg: config_t; m: master_t) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_last(as_stream_config(cfg), m);
  end function;

  function is_sof(cfg: config_t; m: master_t) return boolean
  is
  begin
    return user(cfg, m)(user_sof_c) = '1';
  end function;

  function is_eof(cfg: config_t; m: master_t) return boolean
  is
  begin
    return user(cfg, m)(user_eof_c) = '1';
  end function;

  function is_error(cfg: config_t; m: master_t) return boolean
  is
  begin
    return user(cfg, m)(user_error_c) = '1';
  end function;

  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.keep(as_stream_config(cfg), m, order);
  end function;

  function user(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.user(as_stream_config(cfg), m);
  end function;

  function id(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.id(as_stream_config(cfg), m);
  end function;

  function dest(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.dest(as_stream_config(cfg), m);
  end function;

  function pixels(cfg: config_t; m: master_t) return pixel_vector
  is
    constant data_v: byte_string(0 to cfg.pixel_count * pixel_bytes(cfg) - 1)
      := nsl_amba.axi4_stream.bytes(as_stream_config(cfg), m, BYTE_ORDER_INCREASING);
    constant cb: natural := component_bytes(cfg);
    variable ret: pixel_vector(0 to cfg.pixel_count-1);
    variable base: natural;
    variable v: unsigned(cb*8-1 downto 0);
  begin
    ret := (others => pixel_zero_c);

    for p in 0 to cfg.pixel_count-1
    loop
      for c in 0 to cfg.component_count-1
      loop
        base := p * pixel_bytes(cfg) + c * cb;
        v := from_le(data_v(base to base + cb - 1));
        ret(p)(c) := resize(v, max_component_bits_c);
      end loop;
    end loop;

    return ret;
  end function;

  function pixel(cfg: config_t;
                 m: master_t;
                 index: natural := 0) return pixel_t
  is
    constant all_pixels: pixel_vector := pixels(cfg, m);
  begin
    assert index < cfg.pixel_count
      report "Pixel index is out of beat range"
      severity failure;

    return all_pixels(index);
  end function;

  function transfer(cfg: config_t;
                    pixels: pixel_vector;
                    keep: std_ulogic_vector := na_suv;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    sof: boolean := false;
                    last: boolean := false;
                    eof: boolean := false;
                    error: boolean := false) return master_t
  is
    alias xpixels: pixel_vector(0 to pixels'length-1) is pixels;
    constant cb: natural := component_bytes(cfg);
    variable data_v: byte_string(0 to cfg.pixel_count * pixel_bytes(cfg) - 1);
    variable keep_v: std_ulogic_vector(0 to cfg.pixel_count * pixel_bytes(cfg) - 1);
    variable user_v: std_ulogic_vector(user_width_c-1 downto 0);
    variable base: natural;
  begin
    assert pixels'length = cfg.pixel_count
      report "Bad pixel count"
      severity failure;
    assert keep'length = 0 or keep'length = cfg.pixel_count
      report "Keep is stated per pixel of the beat"
      severity failure;

    for p in 0 to cfg.pixel_count-1
    loop
      for c in 0 to cfg.component_count-1
      loop
        base := p * pixel_bytes(cfg) + c * cb;
        data_v(base to base + cb - 1) := to_le(resize(xpixels(p)(c), cb*8));
      end loop;
    end loop;

    if keep'length = 0 then
      keep_v := (others => '1');
    else
      for p in 0 to cfg.pixel_count-1
      loop
        base := p * pixel_bytes(cfg);
        keep_v(base to base + pixel_bytes(cfg) - 1) := (others => keep(keep'low + p));
      end loop;
    end if;

    user_v := (others => '0');
    if sof then
      user_v(user_sof_c) := '1';
    end if;
    if eof then
      user_v(user_eof_c) := '1';
    end if;
    if error then
      user_v(user_error_c) := '1';
    end if;

    return nsl_amba.axi4_stream.transfer(
      cfg => as_stream_config(cfg),
      bytes => data_v,
      keep => keep_v,
      order => BYTE_ORDER_INCREASING,
      id => id,
      user => user_v,
      dest => dest,
      valid => valid,
      last => last);
  end function;

  function transfer(cfg: config_t;
                    pixel: pixel_t;
                    keep: boolean := true;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    sof: boolean := false;
                    last: boolean := false;
                    eof: boolean := false;
                    error: boolean := false) return master_t
  is
    variable pixel_v: pixel_vector(0 to 0);
    variable keep_v: std_ulogic_vector(0 to 0);
  begin
    assert cfg.pixel_count = 1
      report "Single-pixel transfer needs a one-pixel-wide configuration"
      severity failure;

    pixel_v(0) := pixel;
    if keep then
      keep_v := "1";
    else
      keep_v := "0";
    end if;

    return transfer(cfg => cfg,
                    pixels => pixel_v,
                    keep => keep_v,
                    id => id,
                    dest => dest,
                    valid => valid,
                    sof => sof,
                    last => last,
                    eof => eof,
                    error => error);
  end function;

  function transfer_defaults(cfg: config_t) return master_t
  is
  begin
    return nsl_amba.axi4_stream.transfer_defaults(as_stream_config(cfg));
  end function;

  function accept(cfg: config_t;
                  ready: boolean := false) return slave_t
  is
  begin
    return nsl_amba.axi4_stream.accept(as_stream_config(cfg), ready);
  end function;

  function to_pixel(cfg: config_t; color: nsl_color.rgb.rgb24) return pixel_t
  is
    variable ret: pixel_t := pixel_zero_c;
    variable v: unsigned(max_component_bits_c+7 downto 0);
  begin
    if cfg.colorspace = COLORSPACE_RGB565 then
      ret(0) := color.r(7 downto 3) & color.g(7 downto 2) & color.b(7 downto 3);
      return ret;
    end if;

    assert cfg.component_count >= 3
      report "RGB conversion needs at least three components"
      severity failure;

    for c in 0 to 2
    loop
      case c is
        when 0 => v := resize(color.r, v'length);
        when 1 => v := resize(color.g, v'length);
        when others => v := resize(color.b, v'length);
      end case;

      if cfg.component_bits >= 8 then
        ret(c) := resize(shift_left(v, cfg.component_bits - 8), max_component_bits_c);
      else
        ret(c) := resize(shift_right(v, 8 - cfg.component_bits), max_component_bits_c);
      end if;
    end loop;

    return ret;
  end function;

  function to_rgb24(cfg: config_t; p: pixel_t) return nsl_color.rgb.rgb24
  is
    variable ret: nsl_color.rgb.rgb24;
    variable v: unsigned(max_component_bits_c-1 downto 0);
    variable c8: unsigned(7 downto 0);
  begin
    if cfg.colorspace = COLORSPACE_RGB565 then
      ret.r := p(0)(15 downto 11) & "000";
      ret.g := p(0)(10 downto 5) & "00";
      ret.b := p(0)(4 downto 0) & "000";
      return ret;
    end if;

    assert cfg.component_count >= 3
      report "RGB conversion needs at least three components"
      severity failure;

    for c in 0 to 2
    loop
      v := p(c);

      if cfg.component_bits >= 8 then
        c8 := resize(shift_right(v, cfg.component_bits - 8), 8);
      else
        c8 := resize(shift_left(v, 8 - cfg.component_bits), 8);
      end if;

      case c is
        when 0 => ret.r := c8;
        when 1 => ret.g := c8;
        when others => ret.b := c8;
      end case;
    end loop;

    return ret;
  end function;

  function component_from_byte(cfg: config_t; v: unsigned(7 downto 0)) return component_t
  is
    variable w: unsigned(max_component_bits_c+7 downto 0);
  begin
    w := resize(v, w'length);
    if cfg.component_bits >= 8 then
      return resize(shift_left(w, cfg.component_bits - 8), max_component_bits_c);
    else
      return resize(shift_right(w, 8 - cfg.component_bits), max_component_bits_c);
    end if;
  end function;

  function component_to_byte(cfg: config_t; v: component_t) return unsigned
  is
  begin
    if cfg.component_bits >= 8 then
      return resize(shift_right(v, cfg.component_bits - 8), 8);
    else
      return resize(shift_left(v, 8 - cfg.component_bits), 8);
    end if;
  end function;

  function to_pixel(cfg: config_t; color: nsl_color.ycbcr.ycbcr24) return pixel_t
  is
    variable ret: pixel_t := pixel_zero_c;
  begin
    assert cfg.colorspace = COLORSPACE_YCBCR444
      report "YCbCr conversion needs a YCbCr 4:4:4 configuration"
      severity failure;

    ret(0) := component_from_byte(cfg, color.y);
    ret(1) := component_from_byte(cfg, unsigned(color.cb) xor x"80");
    ret(2) := component_from_byte(cfg, unsigned(color.cr) xor x"80");
    return ret;
  end function;

  function to_ycbcr24(cfg: config_t; p: pixel_t) return nsl_color.ycbcr.ycbcr24
  is
    variable ret: nsl_color.ycbcr.ycbcr24;
  begin
    assert cfg.colorspace = COLORSPACE_YCBCR444
      report "YCbCr conversion needs a YCbCr 4:4:4 configuration"
      severity failure;

    ret.y := component_to_byte(cfg, p(0));
    ret.cb := signed(component_to_byte(cfg, p(1)) xor x"80");
    ret.cr := signed(component_to_byte(cfg, p(2)) xor x"80");
    return ret;
  end function;

  function color(cfg: config_t; c: nsl_color.rgb.rgb24) return pixel_t
  is
    constant n: natural := cfg.component_bits;
    constant code_max: real := 2.0 ** n - 1.0;
    constant code_scale: real := 2.0 ** n / 256.0;
    variable r, g, b, y, cb, cr, kr, kb: real;
    variable ret: pixel_t := pixel_zero_c;

    -- Full range code of a given width, v in [0, 1]
    function full_code(v: real; width: natural) return unsigned is
      constant top: real := 2.0 ** width - 1.0;
    begin
      return to_unsigned(integer(realmax(0.0, realmin(top, round(v * top)))), width);
    end function;

    -- Luma or RGB component, v in [0, 1]
    function luma_code(v: real) return component_t is
      variable code: real;
    begin
      if cfg.quantization = QUANTIZATION_LIMITED then
        code := (16.0 + 219.0 * v) * code_scale;
      else
        code := v * code_max;
      end if;
      return to_unsigned(integer(realmax(0.0, realmin(code_max, round(code)))),
                         max_component_bits_c);
    end function;

    -- Color difference component, v in [-0.5, 0.5]
    function chroma_code(v: real) return component_t is
      variable code: real;
    begin
      if cfg.quantization = QUANTIZATION_LIMITED then
        code := (128.0 + 224.0 * v) * code_scale;
      else
        code := 2.0 ** (n - 1) + v * code_max;
      end if;
      return to_unsigned(integer(realmax(0.0, realmin(code_max, round(code)))),
                         max_component_bits_c);
    end function;
  begin
    r := real(to_integer(c.r)) / 255.0;
    g := real(to_integer(c.g)) / 255.0;
    b := real(to_integer(c.b)) / 255.0;

    case cfg.colorimetry is
      when COLORIMETRY_BT601 =>
        kr := 0.299;
        kb := 0.114;
      when COLORIMETRY_BT709 =>
        kr := 0.2126;
        kb := 0.0722;
    end case;

    y := kr * r + (1.0 - kr - kb) * g + kb * b;
    cb := (b - y) / (2.0 * (1.0 - kb));
    cr := (r - y) / (2.0 * (1.0 - kr));

    case cfg.colorspace is
      when COLORSPACE_RGB =>
        ret(0) := luma_code(r);
        ret(1) := luma_code(g);
        ret(2) := luma_code(b);

      when COLORSPACE_YCBCR444 | COLORSPACE_YCBCR422 =>
        ret(0) := luma_code(y);
        ret(1) := chroma_code(cb);
        ret(2) := chroma_code(cr);

      when COLORSPACE_GRAY =>
        ret(0) := luma_code(y);

      when COLORSPACE_RGB565 =>
        ret(0) := full_code(r, 5) & full_code(g, 6) & full_code(b, 5);

      when COLORSPACE_INDEXED | COLORSPACE_AUTO =>
        assert false
          report "An indexed configuration has no color to show"
          severity failure;
    end case;

    return ret;
  end function;

  function palette(cfg: config_t; colors: nsl_color.rgb.rgb24_vector) return pixel_vector
  is
    alias xcolors: nsl_color.rgb.rgb24_vector(0 to colors'length-1) is colors;
    variable ret: pixel_vector(0 to colors'length-1);
  begin
    for i in ret'range
    loop
      ret(i) := color(cfg, xcolors(i));
    end loop;
    return ret;
  end function;

end package body;
