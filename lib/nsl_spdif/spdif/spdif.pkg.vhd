library ieee;
use ieee.std_logic_1164.all;

library nsl_data;
use nsl_data.crc.all;

package spdif is

  -- Channel A at start of block
  constant PRE_B : std_ulogic_vector := "10011100";
  -- Channel A not at start of block
  constant PRE_M : std_ulogic_vector := "10010011";
  -- Channel B
  constant PRE_W : std_ulogic_vector := "10010110";
  constant BIT_0 : std_ulogic_vector := "10";
  constant BIT_1 : std_ulogic_vector := "11";

  subtype aesebu_crc_t is crc_state(7 downto 0);
  constant aesebu_crc_params_c : crc_params_t := (
    length           => 8,
    init             => 16#00#,
    poly             => 16#b8#,
    complement_input => false,
    insert_msb       => true,
    pop_lsb          => true,
    complement_state => false,
    spill_bitswap    => false,
    spill_lsb_first  => false
    );

end package spdif;
