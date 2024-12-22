library ieee;
use ieee.std_logic_1164.all;

library nsl_data;
use nsl_data.crc.all;
use nsl_data.bytestream.all;

package spdif is

  -- Channel A at start of block
  constant PRE_B : std_ulogic_vector := "10011100";
  -- Channel A not at start of block
  constant PRE_M : std_ulogic_vector := "10010011";
  -- Channel B
  constant PRE_W : std_ulogic_vector := "10010110";
  constant BIT_0 : std_ulogic_vector := "10";
  constant BIT_1 : std_ulogic_vector := "11";

  constant aesebu_crc_params_c : crc_params_t := crc_params(
    init             => "",
    poly             => x"11d",
    complement_input => false,
    complement_state => false,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_DECREASING
    );

end package spdif;
