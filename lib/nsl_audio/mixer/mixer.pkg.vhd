library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_audio, nsl_math, work;

-- Mixing blocks for framed PCM streams.
package mixer is

  -- Mixes two compatible PCM streams, taking metadata from input A.
  -- Gains are non-negative fixed-point values supplied at run time.
  component pcm_mixer is
    generic(
      in_a_config_c : nsl_audio.pcm_stream.config_t;
      in_b_config_c : nsl_audio.pcm_stream.config_t;
      out_config_c : nsl_audio.pcm_stream.config_t;
      guard_bits_c : natural := 4
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_a_i : in nsl_amba.axi4_stream.master_t;
      in_a_o : out nsl_amba.axi4_stream.slave_t;

      in_b_i : in nsl_amba.axi4_stream.master_t;
      in_b_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      gain_a_i : in nsl_math.fixed.ufixed;
      gain_b_i : in nsl_math.fixed.ufixed
      );
  end component;

end package mixer;
