library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.config_t;
use nsl_amba.axi4_stream.master_t;
use nsl_amba.axi4_stream.slave_t;
use nsl_data.endian.endian_t;
use nsl_data.endian.ENDIAN_LITTLE;

-- AXI4-Stream sized framing.
--
-- Converts between two representations of a sequence of frames:
--
-- - Sized: a continuous stream where each frame is preceded by a
--   header of header_length_c bytes encoding the number of following
--   data bytes minus one (header value 0 means 1 data byte).  No
--   tlast is used.  When data_width > 1, the last beat of a frame may
--   be partial; has_keep must be enabled so the consumer can identify
--   valid bytes in that beat.
--
-- - Framed: a normal AXI4-Stream where frame boundaries are marked by
--   tlast.  The all-0xFF header value in the sized stream is reserved
--   and triggers the invalid_o signal on the sized->framed path.
--
-- Sideband signals (id, dest, user) are propagated in both directions.
-- Framing (sized->framed): sideband is forwarded from the input beats.
-- Deframing (framed->sized): header output beats carry the sideband of
-- the first input frame byte; data output beats carry the per-byte
-- sideband stored in the internal FIFO.
package stream_sized is

  -- 1-byte-wide core: sized -> framed.
  --
  -- in_config_c must have data_width = 1 and has_last = false.
  -- out_config_c must have data_width = 1 and has_last = true.
  -- id, dest, user, has_keep and has_strobe must match between in and out configs.
  component axi4_stream_sized_framing_1b is
    generic(
      in_config_c     : config_t;
      out_config_c    : config_t;
      header_length_c : positive range 1 to 4 := 2;
      endian_c        : endian_t := ENDIAN_LITTLE
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      invalid_o : out std_ulogic;

      in_i  : in  master_t;
      in_o  : out slave_t;

      out_o : out master_t;
      out_i : in  slave_t
      );
  end component;

  -- Sized -> framed, any data width.
  --
  -- in_config_c must have has_last = false.
  -- out_config_c must have has_last = true.
  -- id, dest, user, has_keep and has_strobe must match between in and out configs.
  component axi4_stream_sized_framing is
    generic(
      in_config_c     : config_t;
      out_config_c    : config_t;
      header_length_c : positive range 1 to 4 := 2;
      endian_c        : endian_t := ENDIAN_LITTLE
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      invalid_o : out std_ulogic;

      in_i  : in  master_t;
      in_o  : out slave_t;

      out_o : out master_t;
      out_i : in  slave_t
      );
  end component;

  -- 1-byte-wide core: framed -> sized.
  --
  -- in_config_c must have data_width = 1 and has_last = true.
  -- out_config_c must have data_width = 1 and has_last = false.
  -- id, dest, user, has_keep and has_strobe must match between in and out configs.
  component axi4_stream_sized_deframing_1b is
    generic(
      in_config_c      : config_t;
      out_config_c     : config_t;
      header_length_c  : positive range 1 to 4 := 2;
      endian_c         : endian_t := ENDIAN_LITTLE;
      max_frame_size_c : natural  := 2048
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      in_i  : in  master_t;
      in_o  : out slave_t;

      out_o : out master_t;
      out_i : in  slave_t
      );
  end component;

  -- Framed -> sized, any input and output data width.
  --
  -- The input is narrowed to 1 byte internally before processing, so any
  -- in_config_c.data_width is accepted.
  -- in_config_c must have has_last = true.
  -- out_config_c must have has_last = false.
  -- out_config_c must have has_keep = true when data_width > 1, so that
  --   the consumer can identify valid bytes in the partial last beat of
  --   each frame.  Safe without has_keep only when
  --   (header_length_c + every possible data_size) is always a multiple
  --   of out_config_c.data_width.
  -- in/out has_keep and has_strobe must match.
  component axi4_stream_sized_deframing is
    generic(
      in_config_c      : config_t;
      out_config_c     : config_t;
      header_length_c  : positive range 1 to 4 := 2;
      endian_c         : endian_t := ENDIAN_LITTLE;
      max_frame_size_c : natural  := 2048
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      in_i  : in  master_t;
      in_o  : out slave_t;

      out_o : out master_t;
      out_i : in  slave_t
      );
  end component;

  -- Framed -> sized, 1-byte input, any output data width.
  --
  -- Core building block used by axi4_stream_sized_deframing.  Use the
  -- latter for wider framed inputs.
  -- in_config_c must have data_width = 1 and has_last = true.
  -- out_config_c must have has_last = false.
  -- out_config_c must have has_keep = true when data_width > 1 (same
  --   caveat as axi4_stream_sized_deframing above).
  -- in/out has_keep and has_strobe must match.
  component axi4_stream_sized_deframing_1b_to_nb is
    generic(
      in_config_c      : config_t;
      out_config_c     : config_t;
      header_length_c  : positive range 1 to 4 := 2;
      endian_c         : endian_t := ENDIAN_LITTLE;
      max_frame_size_c : natural  := 2048
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      in_i  : in  master_t;
      in_o  : out slave_t;

      out_o : out master_t;
      out_i : in  slave_t
      );
  end component;

end package stream_sized;
