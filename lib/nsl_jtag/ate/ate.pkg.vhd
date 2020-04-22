library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag;

package ate is

  type ate_op is (
    ATE_OP_RESET,
    ATE_OP_RTI,
    ATE_OP_SWD_TO_JTAG_1, -- One third of SWD To JTAG (TMS=001111)
    ATE_OP_SWD_TO_JTAG_23, -- One third of SWD To JTAG (TMS=00111)
    ATE_OP_DR_CAPTURE,
    ATE_OP_IR_CAPTURE,
    ATE_OP_SHIFT
    );
  
  component jtag_ate
    generic (
      data_max_size : positive := 8
      );
    port (
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      divisor_i  : in natural range 0 to 31 := 0;

      cmd_ready_o   : out std_ulogic;
      cmd_valid_i   : in  std_ulogic;
      cmd_op_i      : in  ate_op;
      cmd_data_i    : in  std_ulogic_vector(data_max_size-1 downto 0);
      cmd_size_m1_i : in  natural range 0 to data_max_size-1;

      rsp_ready_i : in std_ulogic := '1';
      rsp_valid_o : out std_ulogic;
      rsp_data_o  : out std_ulogic_vector(data_max_size-1 downto 0);

      jtag_o : out nsl_jtag.jtag.jtag_ate_o;
      jtag_i : in nsl_jtag.jtag.jtag_ate_i
      );
  end component;
  
end package ate;
