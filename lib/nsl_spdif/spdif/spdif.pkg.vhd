library ieee;
use ieee.std_logic_1164.all;

package spdif is

  -- Channel A at start of block
  constant PRE_B : std_ulogic_vector := "10011100";
  -- Channel A not at start of block
  constant PRE_M : std_ulogic_vector := "10010011";
  -- Channel B
  constant PRE_W : std_ulogic_vector := "10010110";
  constant BIT_0 : std_ulogic_vector := "10";
  constant BIT_1 : std_ulogic_vector := "11";

end package spdif;
