library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data;
use nsl_data.crc.all;
use nsl_bnoc.committed.all;

-- Utilities to add/check CRC from a committed interface.  CRC is
-- meant to be added/removed from the N last bytes before the frame
-- validity flit.
--
-- CRC parameters are expressed in nsl_data.crc types. Any CRC size
-- from 1 to 32 bits is supported.  CRC encoding details and
-- serialization are defined there.
--
-- Optionally, frames running through these modules may have a fixed header (in
-- size) of non-protected data.
package crc is

  -- Computes the CRC of the message as it runs through the module, when
  -- validity flit is presented, CRC is appended to the output frame before
  -- forwarding the vailidity.
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

  -- Computes the CRC of the message as it runs through the module, when
  -- validity flit is presented, enough bytes to hold CRC are not forwarded but
  -- compared to the locally calculated value. If CRC values do not match,
  -- frame is marked bad. If a frame that is marked bad is received and
  -- checked, it will be still forwarded, but its validity flit will be
  -- forcibly reset.
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

      valid_o : out std_ulogic;
      out_o  : out committed_req;
      out_i  : in committed_ack
      );
  end component;

end package crc;
