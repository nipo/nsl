library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio;

-- Iterative fixed-point filters for framed PCM streams.
package iir is

  constant max_stage_count_c: natural := 8;
  constant biquad_coefficient_count_c: natural := 5;

  constant coefficient_b0_c: natural := 0;
  constant coefficient_b1_c: natural := 1;
  constant coefficient_b2_c: natural := 2;
  constant coefficient_a1_c: natural := 3;
  constant coefficient_a2_c: natural := 4;

  -- Coefficients are packed stage first, with b0 in the least significant
  -- coefficient_width_c bits, then b1, b2, a1 and a2.  Every field is a
  -- two's-complement Q(coefficient_width_c-coefficient_fraction_bits_c-1).
  -- (coefficient_fraction_bits_c) value.
  component pcm_iir_cascade is
    generic(
      config_c: nsl_audio.pcm_stream.config_t;
      stage_count_c: natural range 1 to max_stage_count_c;
      coefficient_width_c: positive := 24;
      coefficient_fraction_bits_c: natural := 20;
      guard_bits_c: natural := 4
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      in_i: in nsl_amba.axi4_stream.master_t;
      in_o: out nsl_amba.axi4_stream.slave_t;

      out_o: out nsl_amba.axi4_stream.master_t;
      out_i: in nsl_amba.axi4_stream.slave_t;

      coefficients_i: in std_ulogic_vector(
        stage_count_c * biquad_coefficient_count_c * coefficient_width_c - 1
        downto 0);
      flush_i: in std_ulogic := '0'
      );
  end component;

end package iir;
