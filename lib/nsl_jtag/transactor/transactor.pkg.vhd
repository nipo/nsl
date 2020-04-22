library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_jtag;

package transactor is
  
  constant JTAG_SHIFT_BYTE      : std_ulogic_vector(7 downto 0) := "0-------"; -- byte count
  constant JTAG_SHIFT_BYTE_W    : std_ulogic_vector(7 downto 0) := "-1------";
  constant JTAG_SHIFT_BYTE_R    : std_ulogic_vector(7 downto 0) := "--1-----";
  constant JTAG_SHIFT_BIT       : std_ulogic_vector(7 downto 0) := "111-----"; -- bit count
  constant JTAG_SHIFT_BIT_W     : std_ulogic_vector(7 downto 0) := "---1----";
  constant JTAG_SHIFT_BIT_R     : std_ulogic_vector(7 downto 0) := "----1---";
  constant JTAG_CMD_DR_CAPTURE  : std_ulogic_vector(7 downto 0) := "10000000";
  constant JTAG_CMD_IR_CAPTURE  : std_ulogic_vector(7 downto 0) := "10000001";
  constant JTAG_CMD_SWD_TO_JTAG : std_ulogic_vector(7 downto 0) := "10000010";
  constant JTAG_CMD_RESET_CYCLE : std_ulogic_vector(7 downto 0) := "10011---"; -- cycle count
  constant JTAG_CMD_RTI_CYCLE   : std_ulogic_vector(7 downto 0) := "10010---"; -- cycle count
  constant JTAG_CMD_RESET       : std_ulogic_vector(7 downto 0) := "1011----"; -- in packet of 8 cycles
  constant JTAG_CMD_RTI         : std_ulogic_vector(7 downto 0) := "1010----"; -- in packet of 8 cycles
  constant JTAG_CMD_DIVISOR     : std_ulogic_vector(7 downto 0) := "110-----";

  component framed_ate
    port (
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;
      rsp_o   : out nsl_bnoc.framed.framed_req;
      rsp_i   : in nsl_bnoc.framed.framed_ack;

      jtag_o : out nsl_jtag.jtag.jtag_ate_o;
      jtag_i : in nsl_jtag.jtag.jtag_ate_i
      );
  end component;
  
end package transactor;
