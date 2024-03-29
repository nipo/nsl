library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package fsk is

  -- This component gives oscillator frequency for a given channel and
  -- symbol in a FSK frequency plan.
  --
  -- Frequency plan takes the following elaboration-time parameters:
  -- - Total number of channels,
  -- - Channel spacing,
  -- - Frequency stride for symbols,
  -- - Total symbol count,
  -- - Sampling frequency.
  --
  -- Then at any time, for a channel/symbol, it gives the frequency to
  -- feed in the baseband oscillator.
  --
  -- See nsl_signal_generator.nco for oscillator accepting this.
  --
  -- It is actually implemented as an elaboration-time ROM, but this
  -- should be considered to be an implementation detail as this could
  -- be runtime-calculated as well.
  component fsk_frequency_plan is
    generic (
      -- Sampling frequency
      fs_c : real;
      -- Channel 0 center frequency
      channel_0_center_hz_c : real;
      -- Channel separation
      channel_separation_hz_c : real;
      -- Number of channels
      channel_count_c : integer;
      -- Fd for 0
      fd_0_hz_c : real;
      -- Fd increment for each symbol increment
      fd_separation_hz_c : real
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Current channel.
      -- Result for channel_i >= channel_count_c is undefined
      channel_i : in unsigned(nsl_math.arith.log2(channel_count_c)-1 downto 0);

      -- Current symbol
      symbol_i : in unsigned;
      
      -- Instantaneous phase increment for this cycle. Because of
      -- nyquist, (phase_increment_i'left downto 1) should not ever
      -- have a bit set.  Angle in radians/(2*pi).
      phase_increment_o : out ufixed
      );
  end component;    
  
end package fsk;
