library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

package frame_capturer is

  constant CMD_CAPTURE  : nsl_bnoc.framed.framed_data_t := "00000000";
  constant CMD_TRANSMIT : nsl_bnoc.framed.framed_data_t := "00000001";

  component framed_frame_capturer
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      cmd_i : in  nsl_bnoc.framed.framed_req;
      cmd_o : out nsl_bnoc.framed.framed_ack;
      rsp_o : out nsl_bnoc.framed.framed_req;
      rsp_i : in  nsl_bnoc.framed.framed_ack;

      capture_valid_i : in std_ulogic;
      capture_i : in  nsl_bnoc.framed.framed_req;
      transmit_o : out  nsl_bnoc.framed.framed_req;
      transmit_i : in   nsl_bnoc.framed.framed_ack
      );
  end component;

end package frame_capturer;
