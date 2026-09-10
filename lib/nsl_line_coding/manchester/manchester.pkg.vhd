library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package manchester is

  -- Manchester line coding, IEEE-802.3 convention: a '1' bit is
  -- encoded as a low-to-high transition at mid-bit, a '0' bit as a
  -- high-to-low transition.
  --
  -- Both components run in a clock domain oversampling the line:
  -- clock_i_hz_c must be a multiple of 2 * signal_hz_c, at least
  -- 8 * signal_hz_c for the receiver to classify transition timing
  -- reliably.

  component manchester_transmitter
    generic (
      clock_i_hz_c : natural;
      signal_hz_c : natural
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- ready_o strobes once per bit time when transmitter samples
      -- valid_i / bit_i.  Transmission starts on valid_i assertion
      -- and stops after the bit during which valid_i is released.
      ready_o : out std_ulogic;
      valid_i : in std_ulogic;
      bit_i : in std_ulogic;

      -- data_o is only meaningful while active_o is asserted.
      -- active_o covers whole bit cells, from first half of first bit
      -- to second half of last bit.
      active_o : out std_ulogic;
      data_o : out std_ulogic
      );
  end component;

  -- Recovers bits from an oversampled manchester-encoded line.
  -- data_i must already be synchronized (and deglitched if needed) by
  -- caller.
  --
  -- Cell phase (mid-bit vs. cell-boundary transition) is recovered
  -- from transition timing: a full-bit-time interval between
  -- transitions always ends on a mid-bit transition.
  --
  -- A polarity-inverted line yields complemented bits; caller is
  -- expected to resolve polarity from upper-layer framing.
  component manchester_receiver_recovery
    generic (
      clock_i_hz_c : natural;
      signal_hz_c : natural
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      data_i : in std_ulogic;

      -- Strobes once per recovered bit.
      bit_o : out std_ulogic;
      valid_o : out std_ulogic;

      -- Carrier detection: asserted from first transition, released
      -- after line had no transition for more than one bit time.
      active_o : out std_ulogic
      );
  end component;

end package manchester;
