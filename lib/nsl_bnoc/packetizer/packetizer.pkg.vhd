library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
  
package packetizer is

  component committed_packetizer is
    generic(
      header_length_c : natural := 0
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      -- This is captured all the time between frame_i.valid rising for the first
      -- flit in a frame and first cycle with frame_o.ready set.
      frame_header_i : in byte_string(0 to header_length_c-1) := (others => x"00");
      -- This is captured when frame_i.last is set.
      frame_valid_i : in std_ulogic := '1';
      
      frame_i   : in  framed_req;
      frame_o   : out framed_ack;

      packet_o  : out committed_req;
      packet_i  : in committed_ack
      );
  end component;

  component committed_unpacketizer is
    generic(
      header_length_c : natural := 0
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      packet_i  : in  committed_req;
      packet_o  : out committed_ack;

      -- Header and packet validity.
      --
      -- Header is valid from the first frame byte to the last one.
      frame_header_o : out byte_string(0 to header_length_c-1);
      -- Frame vadility information is valid when last flit of frame
      -- is transferred.
      frame_valid_o : out std_ulogic;

      frame_o   : out framed_req;
      frame_i   : in framed_ack
      );
  end component;

end package packetizer;
