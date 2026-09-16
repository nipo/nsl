library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;

-- Moving channels about within a frame.
--
-- A converter states how many channels it has and a processing chain
-- states how many it wants, and the two rarely agree: a guitar goes
-- into one side of a stereo input and comes out of both sides of a
-- stereo output, so what sits either end of the chain is a stream of
-- two channels while the chain itself carries one.
--
-- Nothing here touches a sample.  A channel is picked up and put
-- down somewhere else, sideband bits and all, which is why this is
-- routing and not processing: it is the same audio, differently
-- addressed.
package routing is

  -- Which input channel each output channel takes, output channel 0
  -- first.  An entry naming a channel the input does not carry is
  -- refused at elaboration.
  type channel_map_t is array (natural range <>) of natural;

  -- Rebuilds a frame from channels of another.
  --
  -- Purely combinational, so there is no clock and no latency: the
  -- beat leaving is the beat arriving with its channels elsewhere,
  -- and the framing bits -- packet boundary, block start, error --
  -- are what came in.
  --
  -- Both streams state the same sample width and the same sideband
  -- width; a stream that changes either is doing something to the
  -- audio rather than to its addressing.
  component pcm_channel_map is
    generic(
      in_config_c : work.pcm_stream.config_t;
      out_config_c : work.pcm_stream.config_t;
      map_c : channel_map_t
      );
    port(
      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package routing;
