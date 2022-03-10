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

      params_c : crc_params_t
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

      params_c : crc_params_t
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
