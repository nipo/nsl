library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_jtag, nsl_io;

package transactor is
  
  constant JTAG_SHIFT_BYTE      : nsl_bnoc.framed.framed_data_t := "0-------"; -- byte count
  constant JTAG_SHIFT_BYTE_W    : nsl_bnoc.framed.framed_data_t := "-1------";
  constant JTAG_SHIFT_BYTE_R    : nsl_bnoc.framed.framed_data_t := "--1-----";
  constant JTAG_SHIFT_BIT       : nsl_bnoc.framed.framed_data_t := "111-----"; -- bit count
  constant JTAG_SHIFT_BIT_W     : nsl_bnoc.framed.framed_data_t := "---1----";
  constant JTAG_SHIFT_BIT_R     : nsl_bnoc.framed.framed_data_t := "----1---";
  constant JTAG_CMD_DR_CAPTURE  : nsl_bnoc.framed.framed_data_t := "10000000";
  constant JTAG_CMD_IR_CAPTURE  : nsl_bnoc.framed.framed_data_t := "10000001";
  constant JTAG_CMD_SWD_TO_JTAG : nsl_bnoc.framed.framed_data_t := "10000010";
  constant JTAG_CMD_DIVISOR     : nsl_bnoc.framed.framed_data_t := "10000011"; -- Next byte is divisor
  constant JTAG_CMD_SYS_RESET   : nsl_bnoc.framed.framed_data_t := "1000010-"; -- Set system reset (active high)
  constant JTAG_CMD_RESET_CYCLE : nsl_bnoc.framed.framed_data_t := "10011---"; -- cycle count
  constant JTAG_CMD_RTI_CYCLE   : nsl_bnoc.framed.framed_data_t := "10010---"; -- cycle count
  constant JTAG_CMD_RESET       : nsl_bnoc.framed.framed_data_t := "1011----"; -- in packet of 8 cycles
  constant JTAG_CMD_RTI         : nsl_bnoc.framed.framed_data_t := "1010----"; -- in packet of 8 cycles

  component framed_ate
    port (
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;
      rsp_o   : out nsl_bnoc.framed.framed_req;
      rsp_i   : in nsl_bnoc.framed.framed_ack;

      jtag_o : out nsl_jtag.jtag.jtag_ate_o;
      jtag_i : in nsl_jtag.jtag.jtag_ate_i;

      system_reset_n_o : out nsl_io.io.opendrain
      );
  end component;
  
end package transactor;
