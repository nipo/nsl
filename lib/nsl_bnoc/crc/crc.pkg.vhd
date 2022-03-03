library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data;
use nsl_data.crc.all;
use nsl_bnoc.committed.all;
  
package crc is

  component crc_committed_adder is
    generic(
      -- length not part of CRC
      header_length_c : natural := 0;
      -- CRC parameters, see nsl_data.crc
      crc_init_c : crc_state;
      crc_poly_c : crc_state;
      insert_msb_c : boolean;
      pop_lsb_c : boolean;
      complement_c : boolean;
      -- Output method
      stream_lsb_first_c : boolean;
      bit_reverse_c : boolean
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;
      
      in_i   : in  committed_req;
      in_o   : out committed_ack;

      out_o  : out committed_req;
      out_i  : in committed_ack
      );
  end component;

  component crc_committed_checker is
    generic(
      -- length not part of CRC
      header_length_c : natural := 0;
      -- CRC parameters, see nsl_data.crc
      crc_init_c : crc_state;
      crc_poly_c : crc_state;
      crc_check_c : crc_state;
      insert_msb_c : boolean;
      pop_lsb_c : boolean;
      complement_c : boolean
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;
      
      in_i   : in  committed_req;
      in_o   : out committed_ack;

      out_o  : out committed_req;
      out_i  : in committed_ack
      );
  end component;

end package crc;
