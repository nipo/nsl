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

  -- Inputs 10 bit vector to a single pin using bit_clock_i as serdes
  -- SDR clock.  word_clock_i must be 10x slower than bit_clock_i,
  -- and gearbox_clock_i must be 5x slower than bit_clock_i.
  -- Bit slip and delay control are external.
  -- For series 6, a BUFPLL is needed for the serdes_strobe_i signal
  component serdes_sdr10_input is
    generic(
      left_to_right_c : boolean := false
      );
    port(
      bit_clock_i : in std_ulogic;
      gearbox_clock_i : in std_ulogic := '0';
      word_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      serdes_strobe_i : in std_ulogic := '0';

      serial_i : in std_ulogic;
      -- A descending vector may be bound here, it will be used left to right
      -- or right to left depending on generic.
      parallel_o : out std_ulogic_vector(0 to 9);

      bitslip_i : in std_ulogic;
      mark_o : out std_ulogic
      );
  end component;

  -- Outputs 10 bit vector to a single pin using bit_clock_i as serdes DDR clock.
  -- SDR clock.  word_clock_i must be 10x slower than bit_clock_i,
  -- and gearbox_clock_i must be 5x slower than bit_clock_i.
  -- For series 6, a BUFPLL is needed for the serdes_strobe_i signal
  component serdes_sdr10_output is
    generic(
      -- Whether to send parallel_i from left of vector to right.
      left_to_right_c : boolean := false
      );
    port(
      bit_clock_i : in std_ulogic;
      gearbox_clock_i : in std_ulogic := '0';
      word_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      
      serdes_strobe_i : in std_ulogic := '0';
      -- A descending vector may be bound here, it will be used left to right
      -- or right to left depending on generic.
      parallel_i : in std_ulogic_vector(0 to 9);
      serial_o : out std_ulogic
      );
  end component;

  component serdes_output is
    generic(
      -- Whether to send parallel_i from left or right.
      left_first_c : boolean := false;
      ddr_mode_c : boolean := false;
      -- Whether we are going to delay block
      to_delay_c : boolean := false;
      -- Must be even for ddr mode.
      ratio_c : positive
      );
    port(
      -- * DDR mode: parallel_clock * ratio / 2
      -- * non-DDR mode: parallel_clock * ratio
      serial_clock_i : in std_ulogic;
      parallel_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- This vector will be used left to right or right to left
      -- depending on generic.
      parallel_i : in std_ulogic_vector(0 to ratio_c-1);
      serial_o : out std_ulogic
      );
  end component;

  -- Serialising output that can let go of its pin.
  --
  -- Data behaves as for serdes_output.  The output enable carries one
  -- bit per pair of serial bits, which is the granularity the pad
  -- logic offers: a serialiser holds half as many tristate registers
  -- as data ones, so a pin turns around every second bit at finest.
  -- Enable bit i covers serial bits 2*i and 2*i+1.
  --
  -- The pad side is a tristated pair already moving at pin rate.
  -- Turning it into a wire is the top level's business, which keeps
  -- inout ports out of the hierarchy.  Reading the same pin is a
  -- separate serdes_input, so capture can run off its own clock.
  --
  -- This is not the block a memory PHY wants.  A DRAM data lane needs
  -- its strobe, its mask and its capture built from one tightly
  -- coupled group of vendor primitives, sharing a strobe generator and
  -- fractional-cycle taps that no portable serialiser exposes, so such
  -- a PHY instantiates those primitives itself.  What is here suits a
  -- bidirectional source-synchronous bus whose turnaround falls on a
  -- pair of serial bits.
  component serdes_output_tristated is
    generic(
      -- Whether to send parallel_i from left or right.
      left_first_c : boolean := false;
      ddr_mode_c : boolean := false;
      -- Whether we are going to delay block
      to_delay_c : boolean := false;
      -- Must be even.  Actual limits are dependent on implementation.
      ratio_c : positive
      );
    port(
      -- * DDR mode: parallel_clock * ratio / 2
      -- * non-DDR mode: parallel_clock * ratio
      serial_clock_i : in std_ulogic;
      parallel_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- This vector will be used left to right or right to left
      -- depending on generic.
      parallel_i : in std_ulogic_vector(0 to ratio_c-1);
      -- Follows the same direction as parallel_i.
      output_enable_i : in std_ulogic_vector(0 to ratio_c/2-1);

      pad_o : out nsl_io.io.tristated
      );
  end component;

  component serdes_input is
    generic(
      -- Whether to receive parallel_i from left or right.
      left_first_c : boolean := false;
      -- Whether we sample on rising edge only or on both edges
      ddr_mode_c : boolean := false;
      -- Whether we are from delay block (requires specific inputs in
      -- some implementations)
      from_delay_c : boolean := false;
      -- Must be even for ddr mode.
      -- Actual limits are dependent on implementation.
      ratio_c : positive
      );
    port(
      -- * DDR mode: parallel_clock * ratio / 2
      -- * non-DDR mode: parallel_clock * ratio
      serial_clock_i : in std_ulogic;
      parallel_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      serial_i : in std_ulogic;
      -- Whatever the direction of vector bound here,
      -- parallel word will be set depending on left_first_c.
      parallel_o : out std_ulogic_vector(0 to ratio_c-1);

      bitslip_i : in std_ulogic;
      mark_o : out std_ulogic
      );
  end component;

end package serdes;
