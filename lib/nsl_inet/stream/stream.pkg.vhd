library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;

-- AXI4-Stream transport conventions for the internet protocol suite.
--
-- Every layer exchanges packets over AXI4-Stream configured by
-- stream_config() below: a data width of 1, 2 or 4 bytes, keep, last,
-- and a 1-bit user flag.
--
-- Reject flag
-- ===========
--
-- The user flag is meaningful on the last beat of a packet only.
-- When set, the packet is invalid and must be discarded by whichever
-- component next stores or consumes it.  Only components that
-- validate a whole packet and learn the verdict at the last beat (FCS
-- check, internet checksum check over a full PDU) may set the flag;
-- any other rejection (address filtering, unhandled protocol, bad
-- header) is done by not forwarding the packet at all.  Components
-- that forward packets must propagate the flag unchanged.
--
-- Keep
-- ====
--
-- Beats are packed: keep may only deassert a contiguous group of
-- trailing bytes, and only on the last beat of a packet.  Sparse
-- streams are not supported; components may assert is_packed() on
-- the beats they receive and process only the kept prefix.
--
-- Blocks
-- ======
--
-- An inter-layer stream is a sequence of blocks, each occupying an
-- integer count of beats:
--
-- * the headers of the layers below, forwarded without
--   interpretation.  Their lengths, in order, are the layer's
--   header_length_c generic (each item non-zero);
--
-- * the header or context block belonging to the boundary itself;
--
-- * the payload.
--
-- A layer forwards the listed blocks verbatim, consumes exactly its
-- own header block, produces its own context as a new block, and
-- hands its upper neighbour header_length_c & (its context length).
-- The total transported size of the forwarded blocks is
-- context_byte_count(), the only thing a consumer needs, along with
-- the lengths vector, to locate its data at any width.
--
-- A block shorter than its beat count is padded at its tail
-- (contents first), so fields sit at fixed offsets from the block
-- start.  The one exception is the ethernet frame block on the mac
-- side of the ethernet layer, padded at the front so that the frame
-- contents stay contiguous as on the wire and the payload after the
-- header starts on a beat boundary; its geometry is defined in the
-- stream_mac package.  Every header of the suite above ethernet is
-- a multiple of 4 bytes, so payload blocks never need realignment
-- at supported widths.
--
-- Padding bytes are transported verbatim by forwarding layers;
-- block producers emit zero there.
--
-- Backpressure
-- ============
--
-- A layer never originates slowdown: on the receive path, input
-- ready may only deassert as a consequence of backpressure already
-- present on its output side, or for the layer's bounded per-packet
-- fixed cost (decision cycles plus emitted context beats, including
-- block padding), which must not exceed the duration of a
-- minimum-size packet plus the interpacket gap.  As every
-- receive-side layer strips at least as many bytes as it inserts, a
-- layer honoring this contract adds latency but never sustained
-- backpressure when its consumer keeps up.  Stacks mixing different
-- line rates must absorb the mismatch explicitly, with atomic drop
-- fifos between layers.
--
-- Context blocks
-- ==============
--
-- On the receive path a layer strips its protocol header and
-- produces a fixed-size context block for the upper layer; on the
-- transmit path it consumes the same context block to craft its
-- protocol header.  Context blocks are symmetrical: a context
-- received from layer N can be sent back to layer N to reach the
-- peer it came from.  Fields only meaningful in one direction are
-- ignored, not rejected, in the other.
package stream is

  -- Stream configuration shared by all layers of the suite.
  -- byte_count must be 1, 2 or 4.
  function stream_config(byte_count: natural) return config_t;

  -- Whether beat honors the keep conventions of the suite: keep may
  -- only deassert a contiguous group of trailing bytes, and only on
  -- the last beat of a packet.
  function is_packed(cfg: config_t; m: master_t) return boolean;

  -- Whether beat carries the reject flag, i.e. is a last beat with
  -- the user bit set.
  function is_rejected(cfg: config_t; m: master_t) return boolean;

  -- Returns the beat with the reject flag set to the given value.
  function reject_set(cfg: config_t; m: master_t;
                      rejected: boolean) return master_t;

  -- Total transported size of the blocks whose contents lengths are
  -- given, i.e. the sum of every length rounded up to a whole count
  -- of beats.  Every length must be non-zero.
  function context_byte_count(stream_config: config_t;
                              context_lengths: integer_vector) return integer;
  function context_beat_count(stream_config: config_t;
                              context_lengths: integer_vector) return integer;

  -- Pads one block's contents to its transported size.
  function context_pad(stream_config: config_t;
                       data: byte_string) return byte_string;

  -- The leading size bytes of header.  A layer carrying no context
  -- block ahead of its own gets a null header on an unconstrained
  -- port, whose bounds some synthesizers do not reproduce, so the
  -- header is taken by the size its context lengths imply.
  function context_head(header: byte_string;
                        size: natural) return byte_string;

end package;

package body stream is

  function stream_config(byte_count: natural) return config_t
  is
  begin
    assert byte_count = 1 or byte_count = 2 or byte_count = 4
      report "Stream width must be 1, 2 or 4 bytes"
      severity failure;

    return config(bytes => byte_count,
                  user => 1,
                  keep => true,
                  last => true);
  end function;

  function is_packed(cfg: config_t; m: master_t) return boolean
  is
    constant k: std_ulogic_vector(0 to cfg.data_width-1) := keep(cfg, m);
    variable in_pad: boolean := false;
  begin
    for i in k'range
    loop
      if k(i) /= '1' then
        in_pad := true;
      elsif in_pad then
        return false;
      end if;
    end loop;

    return not in_pad or is_last(cfg, m);
  end function;

  function is_rejected(cfg: config_t; m: master_t) return boolean
  is
  begin
    return is_last(cfg, m) and user(cfg, m)(0) = '1';
  end function;

  function reject_set(cfg: config_t; m: master_t;
                      rejected: boolean) return master_t
  is
    variable ret: master_t := m;
  begin
    ret.user := (others => '-');
    ret.user(0) := to_logic(rejected);
    return ret;
  end function;

  function context_byte_count(stream_config: config_t;
                              context_lengths: integer_vector) return integer
  is
    constant w: integer := stream_config.data_width;
    variable ret: integer := 0;
  begin
    for i in context_lengths'range
    loop
      assert context_lengths(i) > 0
        report "Context lengths must be non-zero"
        severity failure;
      ret := ret + ((context_lengths(i) + w - 1) / w) * w;
    end loop;
    return ret;
  end function;

  function context_beat_count(stream_config: config_t;
                              context_lengths: integer_vector) return integer
  is
  begin
    return context_byte_count(stream_config, context_lengths)
      / stream_config.data_width;
  end function;

  function context_pad(stream_config: config_t;
                       data: byte_string) return byte_string
  is
    constant total_c: integer
      := context_byte_count(stream_config, (0 => data'length));
    constant pad_c: byte_string(data'length to total_c-1) := (others => x"00");
  begin
    return data & pad_c;
  end function;

  function context_head(header: byte_string;
                        size: natural) return byte_string
  is
    variable ret: byte_string(0 to size-1);
  begin
    for i in ret'range
    loop
      ret(i) := header(header'left + i);
    end loop;

    return ret;
  end function;

end package body;
