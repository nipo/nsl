library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package gfsk is

  -- This component is little brother of nsl_sdr/fsk/fsk_frequency_plan for GFSK.
  --
  -- In addition to the FSK frequency plan, it takes the gaussian
  -- characteristics (symbol rate, BT product) as constants.
  --
  -- Output stream is the same, but will be filtered through some
  -- filter approaching ideal gaussian.
  component gfsk_frequency_plan is
    generic (
      -- Sampling frequency
      fs_c : real;
      -- Block clock frequency
      clock_i_hz_c : integer;
      -- Channel 0 center frequency
      channel_0_center_hz_c : real;
      -- Channel separation
      channel_separation_hz_c : real;
      -- Number of channels
      channel_count_c : integer;

      -- Symbol rate
      symbol_rate_c : real;
      -- Bandwidth * Time product
      bt_c : real;
      -- Gaussian filter method, see nsl_dsp.gaussian
      gfsk_method_c : string := "box"
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
  
end package gfsk;
