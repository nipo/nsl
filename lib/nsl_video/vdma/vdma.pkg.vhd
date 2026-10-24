library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_video;

-- Video DMAs between pixel streams and AXI4-MM memory.
--
-- Memory layout
-- =============
--
-- A frame is stored as lines of bytes. Line y starts at address
-- base + y * stride. Within a line, the bytes of the stream beats are
-- stored in stream order at increasing addresses, byte 0 of the first
-- beat at the line start address: TDATA byte i of a beat goes to the
-- address following byte i-1. DMAs never look at pixel components, any
-- pixel_stream configuration can be stored and read back as long as
-- both sides use the same one.
--
-- Stream beat width (S bytes) and memory data width (M bytes, from the
-- AXI4-MM configuration) are independent. A line of L bytes is stored
-- as ceil(L / M) memory words, the last one written with partial
-- strobes. A line is carried on the stream as ceil(L / S) beats; when
-- L is not a multiple of S, the last beat of the line has partial
-- TKEEP, so the stream configuration needs TKEEP. Without TKEEP, every
-- beat is full. TKEEP must be contiguous from byte 0.
--
-- Base addresses and stride must be multiples of M; low address bits
-- are ignored. Stride is the byte distance between line starts and
-- must be at least the line length.
--
-- Bursts
-- ======
--
-- DMAs issue INCR bursts of full-width beats. A burst never crosses an
-- address multiple of M * 2**burst_length_l2_c, which is clamped to
-- the maximum length allowed by the AXI4-MM configuration and to
-- 4 KiB, so bursts never cross a 4 KiB boundary. A burst never spans
-- two lines.  All transactions use ID 0, and responses are expected in
-- order.
--
-- Clocking
-- ========
--
-- Both DMAs run in the memory clock domain. Pixel streams in the
-- camera or display clock domain must be crossed with a dual-clock
-- stream FIFO outside of the DMA (e.g.
-- nsl_amba.stream_fifo.axi4_stream_fifo with clock_count_c = 2).
package vdma is

  -- Outcome of a frame, valid along with the done pulse.
  type frame_status_t is
  record
    -- Frame may be displayed: it ended with EOF, and none of the
    -- error flags below is set.
    complete: std_ulogic;
    -- A SOF came before the EOF of the frame.
    truncated: std_ulogic;
    -- At least one line was flagged with the pixel_stream ERROR bit.
    line_error: std_ulogic;
    -- Lines beyond the height limit, or bytes beyond the stride were
    -- dropped.
    overflow: std_ulogic;
    -- At least one bus transaction got a SLVERR or DECERR response.
    bus_error: std_ulogic;
  end record;

  -- Writes a pixel stream to memory.
  --
  -- Beats are ignored until the first beat of a line flagged SOF.
  -- base_i, stride_i and max_height_i are sampled when a SOF is seen,
  -- and start_o pulses at the same time.  A scheduler may change them
  -- at any time, they are only taken into account for the next frame.
  --
  -- Lines are written at base + y * stride. Lines beyond max_height_i
  -- and bytes beyond stride_i in a line are dropped and flag overflow.
  --
  -- A frame ends at the line flagged EOF, or at the next SOF if it
  -- comes earlier, which makes the frame truncated. Once every write
  -- response of the frame is received, done_o pulses for one cycle
  -- with status_o.
  --
  -- Line data is buffered in a buffer_depth_c memory word FIFO. An
  -- address is issued only once the whole burst data is in the FIFO,
  -- so write data never stalls the bus once a burst starts.
  -- buffer_depth_c must be at least the burst length; twice the burst
  -- length allows streaming one burst while filling the next one.
  component vdma_writer is
    generic(
      mem_config_c : nsl_amba.axi4_mm.config_t;
      stream_config_c : nsl_video.pixel_stream.config_t;
      burst_length_l2_c : natural := 4;
      buffer_depth_c : positive := 32;
      size_width_c : positive := 16
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      base_i : in unsigned(mem_config_c.address_width-1 downto 0);
      stride_i : in unsigned(mem_config_c.address_width-1 downto 0);
      max_height_i : in unsigned(size_width_c-1 downto 0);

      start_o : out std_ulogic;
      done_o : out std_ulogic;
      status_o : out frame_status_t;

      stream_i : in nsl_video.pixel_stream.master_t;
      stream_o : out nsl_video.pixel_stream.slave_t;

      mem_o : out nsl_amba.axi4_mm.master_t;
      mem_i : in nsl_amba.axi4_mm.slave_t
      );
  end component;

  -- Reads a frame from memory as a pixel stream.
  --
  -- When start_i is asserted while ready_o is high, base_i, stride_i,
  -- width_i and height_i are sampled. width_i is the line length in
  -- bytes (pixel count times pixel byte count), height_i the line count
  -- in memory. Both must be non-zero.
  --
  -- The frame is emitted as height_i * line_repeat_c lines: each memory
  -- line is read line_repeat_c times in a row. SOF is set on the first
  -- beat of the frame, EOF on the last one, ERROR is never set.
  --
  -- Read data goes to a buffer_depth_c memory word FIFO. Bursts are
  -- issued as long as the FIFO has room for their whole data, so
  -- multiple bursts are outstanding and the read data channel is never
  -- back-pressured. Prefetching only stops when the FIFO is full: the
  -- output stream may be stalled for a long time (e.g. during display
  -- blanking) without losing anything. A buffer of at least a line
  -- lets the next line be ready before it is needed.
  --
  -- ready_o rises again once every read response of the frame is
  -- received, which may be well before the last beat goes out of the
  -- FIFO. done_o pulses at that time with status_o, only bus_error and
  -- complete are meaningful. When done_o pulses, the frame buffer is
  -- not used by the reader anymore.
  component vdma_reader is
    generic(
      mem_config_c : nsl_amba.axi4_mm.config_t;
      stream_config_c : nsl_video.pixel_stream.config_t;
      burst_length_l2_c : natural := 4;
      buffer_depth_c : positive := 256;
      size_width_c : positive := 16;
      line_repeat_c : positive := 1
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      base_i : in unsigned(mem_config_c.address_width-1 downto 0);
      stride_i : in unsigned(mem_config_c.address_width-1 downto 0);
      width_i : in unsigned(size_width_c-1 downto 0);
      height_i : in unsigned(size_width_c-1 downto 0);
      start_i : in std_ulogic;
      ready_o : out std_ulogic;

      done_o : out std_ulogic;
      status_o : out frame_status_t;

      mem_o : out nsl_amba.axi4_mm.master_t;
      mem_i : in nsl_amba.axi4_mm.slave_t;

      stream_o : out nsl_video.pixel_stream.master_t;
      stream_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- Byte gearbox between two packet streams of different widths,
  -- used internally by the DMAs. Packet bytes are repacked from byte 0
  -- of the first output beat, the last output beat of a packet has
  -- partial TKEEP if needed. User bits of the first input beat of a
  -- packet go to the first output beat, user bits of the last input
  -- beat go to the last output beat, other output beats have no user
  -- bits. ID and DEST are not carried. One packet at a time is in the
  -- gearbox. When both widths are equal, it is a passthrough.
  component vdma_gearbox is
    generic(
      in_config_c : nsl_amba.axi4_stream.config_t;
      out_config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- Effective log2 of the burst beat count for a memory configuration
  -- and a requested burst length.
  function burst_length_l2(mem_config: nsl_amba.axi4_mm.config_t;
                           requested_l2: natural) return natural;

end package;

package body vdma is

  function burst_length_l2(mem_config: nsl_amba.axi4_mm.config_t;
                           requested_l2: natural) return natural
  is
    variable ret: natural := requested_l2;
  begin
    if ret > mem_config.len_width then
      ret := mem_config.len_width;
    end if;
    if ret > 12 - mem_config.data_bus_width_l2 then
      ret := 12 - mem_config.data_bus_width_l2;
    end if;
    return ret;
  end function;

end package body;
