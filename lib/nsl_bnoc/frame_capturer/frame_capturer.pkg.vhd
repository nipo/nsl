library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;

package frame_capturer is

  constant CMD_CAPTURE  : framed_data_t := "-------0";
  constant CMD_TRANSMIT : framed_data_t := "-------1";

  component framed_frame_capturer
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      cmd_i : in  framed_req;
      cmd_o : out framed_ack;
      rsp_o : out framed_req;
      rsp_i : in  framed_ack;

      capture_valid_i : in std_ulogic;
      capture_i : in  framed_req;
      transmit_o : out  framed_req;
      transmit_i : in   framed_ack
      );
  end component;

  component committed_frame_gateway
    generic(
      timeout_c : natural := 125000000
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      cmd_i : in  framed_req;
      cmd_o : out framed_ack;
      rsp_o : out framed_req;
      rsp_i : in  framed_ack;

      rx_i : in  committed_req;
      rx_o : out committed_ack;
      tx_o : out committed_req;
      tx_i : in  committed_ack
      );
  end component;

end package frame_capturer;
