library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

-- Timestamp capture register file for frame timestamping sidebands
-- (see nsl_mii.timestamping): a strobe samples the time base into
-- the register the identifier designates.
package capture is

  -- 2 ** id_bits_c registers, written from timestamp_i on strobe_i,
  -- indexed by the id_bits_c low bits of the identifier.
  --
  -- The read port is combinational: read_timestamp_o is the register
  -- read_id_i designates.  Registers are reused as identifiers
  -- cycle, so a consumer must latch the value as soon as it learns
  -- its identifier.
  --
  -- The reader may live in another clock domain than clock_i: no
  -- synchronization is needed as long as the register is stable
  -- while it is read, which the timestamping contract guarantees --
  -- written a synchronizer latency after the frame's strobe, read a
  -- stream-path latency after it, reused 2**id_bits_c frames
  -- later.
  component timestamp_capture is
    generic(
      id_bits_c : natural range 1 to 4 := 2
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      timestamp_i : in timestamp_t;
      strobe_i : in std_ulogic;
      id_i : in unsigned(3 downto 0);

      read_id_i : in unsigned(3 downto 0);
      read_timestamp_o : out timestamp_t
      );
  end component;

end package;
