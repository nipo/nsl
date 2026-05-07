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
-- - Sized: a continuous byte stream where each frame is preceded by a
--   header of header_length_c bytes encoding the number of following
--   data bytes (off by one: header value 0 means 1 data byte).  No
--   tlast is used.  The all-0xFF header value is reserved and triggers
--   the invalid_o signal.
--
-- - Framed: a normal AXI4-Stream where frame boundaries are marked by
--   tlast.
--
-- Sideband signals (id, dest, user) present in both configurations are
-- propagated.  In the framing direction they are forwarded from the
-- input data beats.  In the deframing direction the sideband captured
-- from the first beat of each input frame is replayed on the header
-- bytes; subsequent data bytes carry the sideband stored in the
-- internal FIFO.
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

end package stream_sized;
