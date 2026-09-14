library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_data, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_audio.pcm.all;

-- This package carries PCM audio over AXI4-Stream.
--
-- A beat is a frame: one sample of every channel, all of them at once.
-- Audio is slow, so a wide beat costs registers rather than
-- throughput -- eight channels of four bytes is half the byte lanes a
-- stream may have, at forty eight thousand beats a second -- and every
-- sink wants a frame at a time anyway.  Narrowing to a bus that cannot
-- take a whole frame is a width conversion, which is somebody else's
-- component and not a property of this one.
--
-- A packet is a block: frames_per_packet of them, TLAST on the last.
-- Blocks because that is what IEC 60958 needs -- one bit of channel
-- status per frame per channel, so nothing can be read out of U or C
-- until a whole block of them has arrived, and a packet boundary is
-- what tells a reader where bit zero was.  192 frames is also 4ms at
-- forty eight kilohertz, which is a sane thing for a FIFO to hold and
-- for a DMA descriptor to write.  A transport with no block of its own
-- picks whatever length suits it.
--
-- Two TUSER bits carry what a packet boundary cannot say by itself:
--
-- - BLOCK, on the first beat of a packet, when that packet really does
--   open a block of channel status.  A transport with no blocks never
--   sets it, and then U and C mean nothing.
-- - ERROR, on the TLAST beat, telling the packet is not to be trusted.
--
-- The rest of TUSER is sideband, sideband_bits of it per channel,
-- channel 0 first.  It goes there rather than into TDATA so that TDATA
-- stays nothing but interleaved samples: a stream written to memory is
-- then a buffer something else can play, rather than one with V, U and
-- C bits scattered through it.  TUSER is sixty four bits at most, so
-- sideband has to fit alongside the framing bits -- eight channels of
-- three bits does, eight of eight does not.
--
-- Samples are byte aligned in TDATA, least significant byte first,
-- channel 0 first.  A sample narrower than its bytes is right aligned
-- in them and sign extended when the coding says so, so what a reader
-- gets is the number rather than a field to shift.
--
-- The rate is not here.  A stream says nothing about how fast it
-- runs: it is measured, or stated out of band, and it may change
-- without anything about the stream's shape changing.  A rate travels
-- beside the stream as an nsl_audio.pcm.rate_t.
--
-- Wire-level signals are plain nsl_amba.axi4_stream master/slave
-- records, so any existing AXI4-Stream component operates on such a
-- stream unchanged.  This package only adds a configuration record
-- enforcing the framing and user width relationships, and
-- accessors/constructors expressing beats in terms of frames.
package pcm_stream is

  subtype master_t is nsl_amba.axi4_stream.master_t;
  subtype slave_t is nsl_amba.axi4_stream.slave_t;
  subtype bus_t is nsl_amba.axi4_stream.bus_t;

  subtype master_vector is nsl_amba.axi4_stream.master_vector;
  subtype slave_vector is nsl_amba.axi4_stream.slave_vector;
  subtype bus_vector is nsl_amba.axi4_stream.bus_vector;

  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');

  -- TUSER bit assignment.  Sideband follows the framing bits, so
  -- channel c holds its own at user_sideband_c + c * sideband_bits.
  constant user_block_c: natural := 0;
  constant user_error_c: natural := 1;
  constant user_sideband_c: natural := 2;

  -- Frame layout of a beat, and the AXI4-Stream configuration that
  -- carries it.  The stream configuration is held rather than derived
  -- on use: accessors run in RTL, and deriving there would put the
  -- derivation itself in the logic.
  type config_t is
  record
    stream: nsl_amba.axi4_stream.config_t;
    channel_count: natural range 1 to max_channel_count_c;
    sample_bits: natural range 1 to max_sample_bits_c;
    sideband_bits: natural range 0 to max_sideband_bits_c;
    coding: coding_t;
    frames_per_packet: natural;
  end record;

  type config_vector is array (natural range <>) of config_t;

  -- Bytes one sample takes in TDATA.
  function sample_bytes(cfg: config_t) return natural;
  -- Bytes one frame takes in TDATA.
  function frame_bytes(cfg: config_t) return natural;
  -- Bits of TUSER a stream of this shape needs.
  function user_width(cfg: config_t) return natural;

  -- Underlying AXI4-Stream configuration.  Data width follows the
  -- channel count, user width follows the framing bits and the
  -- sideband, and last is always present: it is what states a block
  -- boundary.
  function as_stream_config(cfg: config_t) return nsl_amba.axi4_stream.config_t;
  -- Whether beats may be held back.
  function has_ready(cfg: config_t) return boolean;

  function config(
    channels: natural range 1 to max_channel_count_c := 2;
    sample_bits: natural range 1 to max_sample_bits_c := 24;
    sideband_bits: natural range 0 to max_sideband_bits_c := 0;
    coding: coding_t := CODING_SIGNED;
    frames_per_packet: natural := block_frame_count_c;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    ready: boolean := true) return config_t;

  function is_valid(cfg: config_t; m: master_t) return boolean;
  function is_ready(cfg: config_t; s: slave_t) return boolean;
  -- Whether a beat changes hands this cycle.
  function is_taken(cfg: config_t; m: master_t; s: slave_t) return boolean;
  -- Beat closes a packet.
  function is_last(cfg: config_t; m: master_t) return boolean;
  -- Beat opens a packet that is also a block of channel status.  Only
  -- meaningful on a beat opening a packet.
  function is_block(cfg: config_t; m: master_t) return boolean;
  -- Packet the beat closes is not to be trusted.  Only meaningful on a
  -- beat closing a packet.
  function is_error(cfg: config_t; m: master_t) return boolean;

  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  function user(cfg: config_t; m: master_t) return std_ulogic_vector;
  function id(cfg: config_t; m: master_t) return std_ulogic_vector;
  function dest(cfg: config_t; m: master_t) return std_ulogic_vector;

  -- The frame the beat carries.  Channels above channel_count read as
  -- zero, and so does sideband a stream states none of.
  function frame(cfg: config_t; m: master_t) return frame_t;

  function transfer(cfg: config_t;
                    frame: frame_t;
                    keep: boolean := true;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    last: boolean := false;
                    block_start: boolean := false;
                    error: boolean := false) return master_t;

  function transfer_defaults(cfg: config_t) return master_t;

  function accept(cfg: config_t;
                  ready: boolean := false) return slave_t;

end package;

package body pcm_stream is

  function sample_bytes(cfg: config_t) return natural
  is
  begin
    return nsl_audio.pcm.sample_bytes(cfg.sample_bits);
  end function;

  function frame_bytes(cfg: config_t) return natural
  is
  begin
    return cfg.channel_count * sample_bytes(cfg);
  end function;

  function user_width(cfg: config_t) return natural
  is
  begin
    return user_sideband_c + cfg.channel_count * cfg.sideband_bits;
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
    channels: natural range 1 to max_channel_count_c := 2;
    sample_bits: natural range 1 to max_sample_bits_c := 24;
    sideband_bits: natural range 0 to max_sideband_bits_c := 0;
    coding: coding_t := CODING_SIGNED;
    frames_per_packet: natural := block_frame_count_c;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    ready: boolean := true) return config_t
  is
    constant frame_bytes_c: natural
      := channels * nsl_audio.pcm.sample_bytes(sample_bits);
    constant user_c: natural := user_sideband_c + channels * sideband_bits;
  begin
    assert frame_bytes_c <= nsl_amba.axi4_stream.max_data_width_c
      report "Frame does not fit in maximum stream data width"
      severity failure;
    assert user_c <= nsl_amba.axi4_stream.max_user_width_c
      report "Framing bits and sideband do not fit in maximum stream user width"
      severity failure;
    assert frames_per_packet /= 0
      report "A packet holds at least one frame"
      severity failure;

    return config_t'(
      stream => nsl_amba.axi4_stream.config(
        bytes => frame_bytes_c,
        user => user_c,
        id => id,
        dest => dest,
        keep => keep,
        strobe => false,
        ready => ready,
        last => true),
      channel_count => channels,
      sample_bits => sample_bits,
      sideband_bits => sideband_bits,
      coding => coding,
      frames_per_packet => frames_per_packet);
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

  function is_block(cfg: config_t; m: master_t) return boolean
  is
  begin
    return user(cfg, m)(user_block_c) = '1';
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

  function frame(cfg: config_t; m: master_t) return frame_t
  is
    constant data_v: byte_string(0 to frame_bytes(cfg) - 1)
      := nsl_amba.axi4_stream.bytes(as_stream_config(cfg), m, BYTE_ORDER_INCREASING);
    constant user_v: std_ulogic_vector := user(cfg, m);
    constant sb: natural := sample_bytes(cfg);
    variable ret: frame_t;
    variable base: natural;
  begin
    ret := frame_zero_c;

    for c in 0 to cfg.channel_count-1
    loop
      base := c * sb;
      ret(c).sample := to_sample(from_le(data_v(base to base + sb - 1)),
                                 cfg.coding);

      for b in 0 to cfg.sideband_bits-1
      loop
        ret(c).sideband(b) := user_v(user_sideband_c + c * cfg.sideband_bits + b);
      end loop;
    end loop;

    return ret;
  end function;

  function transfer(cfg: config_t;
                    frame: frame_t;
                    keep: boolean := true;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    last: boolean := false;
                    block_start: boolean := false;
                    error: boolean := false) return master_t
  is
    constant sb: natural := sample_bytes(cfg);
    variable data_v: byte_string(0 to frame_bytes(cfg) - 1);
    variable keep_v: std_ulogic_vector(0 to frame_bytes(cfg) - 1);
    variable user_v: std_ulogic_vector(user_width(cfg)-1 downto 0);
    variable base: natural;
  begin
    user_v := (others => '0');

    for c in 0 to cfg.channel_count-1
    loop
      base := c * sb;
      data_v(base to base + sb - 1) := to_le(resize(frame(c).sample, sb*8));

      for b in 0 to cfg.sideband_bits-1
      loop
        user_v(user_sideband_c + c * cfg.sideband_bits + b) := frame(c).sideband(b);
      end loop;
    end loop;

    if keep then
      keep_v := (others => '1');
    else
      keep_v := (others => '0');
    end if;

    if block_start then
      user_v(user_block_c) := '1';
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

end package body;
