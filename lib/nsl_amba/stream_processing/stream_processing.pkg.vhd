library ieee;
use ieee.std_logic_1164.all;

library nsl_amba;
use nsl_amba.axi4_stream.config_t;
use nsl_amba.axi4_stream.master_t;
use nsl_amba.axi4_stream.slave_t;

-- AXI4-Stream payload processing blocks.
--
-- Components in this subset rework the byte payload of a stream
-- without interpreting it: they move bytes across lanes and beats.
-- Sideband user bits are treated as per-byte-lane attributes and
-- follow their byte, as recommended by the AXI4-Stream specification
-- for TUSER of width N * data width.
package stream_processing is

  -- Byte-lane packer.
  --
  -- Takes a stream where beats may have strobe gaps (any subset of
  -- lanes enabled, in any position) and emits a stream of full beats
  -- where every lane is enabled.  Byte order is preserved, but a byte
  -- coming in on a given lane may leave on any lane.
  --
  -- config_c must have has_strobe set and has_last cleared: packing
  -- merges bytes of successive input beats in one output beat, which
  -- has no meaningful framing semantics.  For the same reason,
  -- has_keep, id_width and dest_width must be left unused.
  -- user_width must be a multiple of data_width.
  --
  -- Only full beats are emitted, so an accumulation that never
  -- reaches data_width bytes stays in the buffer forever.  There is
  -- no flush: with has_last forbidden, the stream has no boundary at
  -- which a partial beat could be pushed out.
  --
  -- in_o.ready is combinationally derived from out_i.ready; this
  -- block does not break the ready chain.
  component axi4_stream_packer is
    generic(
      config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

end package stream_processing;
