library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_video, work;

-- DVI signal driver
package transceiver is

  component dvi_driver is
    generic(
      driver_mode_c : string := "default"
      );
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;
      serial_clock_i : in std_ulogic;
      
      tmds_i : in work.dvi.symbol_vector_t;

      clock_o : out nsl_io.diff.diff_pair;
      data_o : out nsl_io.diff.diff_pair_vector(0 to 2)
      );
  end component;

  -- Reads a DVI signal back off the wire.
  --
  -- The link brings its own clock, which a PLL turns into the bit
  -- clock the lanes are sampled on and the pixel clock everything
  -- downstream runs on.  Both come from the one PLL so they keep a
  -- known phase to each other.
  --
  -- Each lane then has to be told where its bits sit and where its
  -- symbols start, which is what the delay and the bit slip are for.
  -- What a lane is held against is the control symbols: they are the
  -- only ten-bit words that can be recognised without knowing what
  -- pixels to expect, and blanking is full of them.  It is how many
  -- of them turn up that counts, not whether any do: four of the 1024
  -- ten-bit words are control symbols, so a lane sampled anywhere at
  -- all throws one up every few hundred symbols by chance, and a test
  -- for mere presence locks onto nothing at all quite happily.
  --
  -- The differential receiver is in the pad, so what comes in here is
  -- one signal per pair.
  --
  -- Lanes are aligned one at a time and to themselves alone.  What
  -- remains after this is the skew between them, which a cable and a
  -- board put there and which no per-lane alignment can see.
  component dvi_receiver is
    generic(
      mode_c : nsl_video.mode.mode_t;
      window_l2_c : natural := 12;
      control_min_c : natural := 256;
      control_run_min_c : natural := 16
      );
    port(
      reset_n_i : in std_ulogic;

      clock_i : in std_ulogic;
      data_i : in std_ulogic_vector(0 to 2);

      -- Hold this to make every lane look for its symbol boundary
      -- again, without the source being told anything.
      realign_i : in std_ulogic := '0';

      pixel_clock_o : out std_ulogic;
      -- Five times the above, for a transmitter forwarding what this
      -- receives: made together, the two keep step.
      serial_clock_o : out std_ulogic;
      locked_o : out std_ulogic;

      aligned_o : out std_ulogic_vector(0 to 2);
      control_o : out std_ulogic_vector(0 to 2);

      tmds_o : out work.dvi.symbol_vector_t
      );
  end component;

end package;
