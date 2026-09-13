library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

  function config(
    pixels: natural := 1;
    components: natural range 1 to max_component_count_c := 3;
    component_bits: natural range 1 to max_component_bits_c := 8;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    ready: boolean := true) return config_t;

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

  -- RGB conversion, for the usual three-component configuration.
  -- Components narrower than eight bits are left-aligned in the
  -- rgb24 component, wider ones are truncated.
  function to_pixel(cfg: config_t; color: nsl_color.rgb.rgb24) return pixel_t;
  function to_rgb24(cfg: config_t; p: pixel_t) return nsl_color.rgb.rgb24;

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

  function config(
    pixels: natural := 1;
    components: natural range 1 to max_component_count_c := 3;
    component_bits: natural range 1 to max_component_bits_c := 8;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    ready: boolean := true) return config_t
  is
    constant pixel_bytes_c: natural
      := components * ((component_bits + 7) / 8);
  begin
    assert pixels * pixel_bytes_c <= nsl_amba.axi4_stream.max_data_width_c
      report "Beat does not fit in maximum stream data width"
      severity failure;

    return config_t'(
      stream => nsl_amba.axi4_stream.config(
        bytes => pixels * pixel_bytes_c,
        user => user_width_c,
        id => id,
        dest => dest,
        keep => keep,
        strobe => false,
        ready => ready,
        last => true),
      pixel_count => pixels,
      component_count => components,
      component_bits => component_bits);
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

end package body;
