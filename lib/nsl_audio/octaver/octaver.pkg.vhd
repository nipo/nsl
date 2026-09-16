library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_audio, work;

-- A small set of octave effects for framed PCM streams.
package octaver is

  -- Divide the apparent pitch by two by multiplying each channel by a
  -- square local oscillator. The oscillator toggles at negative-to-
  -- nonnegative zero crossings, so it is locked to the incoming pitch.
  --
  -- The input and output configurations must describe the same signed PCM
  -- frame shape. The effect keeps its crossing state across packet
  -- boundaries, as the audio stream is continuous across those boundaries.
  -- The output is the effected signal only. Use pcm_mixer to add a dry path.
  component pcm_octaver is
    generic(
      in_config_c : nsl_audio.pcm_stream.config_t;
      out_config_c : nsl_audio.pcm_stream.config_t
       );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package octaver;
