library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package serdes is

  -- Outputs 10 bit vector to a single pin using bit_clock_i as serdes DDR clock.
  -- word_clock_i must be 5x slower than bit_clock_i.
  component serdes_ddr10_output is
    generic(
      -- Whether to send parallel_i from left of vector to right.
      left_to_right_c : boolean := false
      );
    port(
      bit_clock_i : in std_ulogic;
      word_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      -- A descending vector may be bound here, it will be used left to right
      -- or right to left depending on generic.
      parallel_i : in std_ulogic_vector(0 to 9);
      serial_o : out std_ulogic
      );
  end component;

  -- Inputs 10 bit vector to a single pin using bit_clock_i as serdes
  -- DDR clock.  word_clock_i must be 5x slower than bit_clock_i.
  -- Bit slip and delay control are external.
  component serdes_ddr10_input is
    generic(
      left_to_right_c : boolean := false
      );
    port(
      bit_clock_i : in std_ulogic;
      word_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      serial_i : in std_ulogic;
      -- A descending vector may be bound here, it will be used left to right
      -- or right to left depending on generic.
      parallel_o : out std_ulogic_vector(0 to 9);

      bitslip_i : in std_ulogic;
      mark_o : out std_ulogic
      );
  end component;

end package serdes;
