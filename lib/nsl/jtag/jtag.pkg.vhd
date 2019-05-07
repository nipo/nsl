library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;

package jtag is
  
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

  type ate_op is (
    ATE_OP_RESET,
    ATE_OP_RTI,
    ATE_OP_SWD_TO_JTAG_3, -- One third of SWD To JTAG (TMS=001111)
    ATE_OP_DR_CAPTURE,
    ATE_OP_IR_CAPTURE,
    ATE_OP_SHIFT
    );

  component jtag_framed_ate
    port (
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      cmd_i   : in nsl.framed.framed_req;
      cmd_o   : out nsl.framed.framed_ack;
      rsp_o   : out nsl.framed.framed_req;
      rsp_i   : in nsl.framed.framed_ack;

      tck_o  : out std_ulogic;
      tms_o  : out std_ulogic;
      tdi_o  : out std_ulogic;
      tdo_i  : in  std_ulogic
      );
  end component;
  
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

      tck_o  : out std_ulogic;
      tms_o  : out std_ulogic;
      tdi_o  : out std_ulogic;
      tdo_i  : in  std_ulogic
      );
  end component;
  
  component jtag_tap_controller is
    port(
      tck_i  : in  std_ulogic;
      tms_i  : in  std_ulogic;
      trst_i : in  std_ulogic := '0';

      reset_o      : out std_ulogic;
      run_o        : out std_ulogic;
      ir_capture_o : out std_ulogic;
      ir_shift_o   : out std_ulogic;
      ir_update_o  : out std_ulogic;
      dr_capture_o : out std_ulogic;
      dr_shift_o   : out std_ulogic;
      dr_update_o  : out std_ulogic
      );
  end component;

  component jtag_tap is
    generic(
      ir_len : natural
      );
    port(
      tck_i  : in  std_ulogic;
      tdi_i  : in  std_ulogic;
      tdo_o  : out std_ulogic;
      tms_i  : in  std_ulogic;
      trst_i : in  std_ulogic := '0';

      -- Default instruction is the value loaded to IR when passing
      -- through TLR. Per spec, it must either be IDCODE instruction
      -- (if implemented), or BYPASS.
      default_instruction_i   : in  std_ulogic_vector(ir_len - 1 downto 0) := (others => '1');

      ir_o         : out std_ulogic_vector(ir_len - 1 downto 0);
      ir_out_i     : in  std_ulogic_vector(ir_len - 1 downto 2);

      reset_o       : out std_ulogic;
      run_o         : out std_ulogic;
      dr_capture_o  : out std_ulogic;
      dr_shift_o    : out std_ulogic;
      dr_update_o   : out std_ulogic;
      dr_tdi_o      : out std_ulogic;
      dr_tdo_i      : in  std_ulogic
      );
  end component;

  component jtag_tap_dr is
    generic(
      ir_len : natural;
      dr_len : natural
      );
    port(
      tck_i         : in  std_ulogic;
      tdi_i         : in  std_ulogic;
      tdo_o         : out std_ulogic;

      match_ir_i   : in  std_ulogic_vector(ir_len - 1 downto 0);
      current_ir_i : in  std_ulogic_vector(ir_len - 1 downto 0);
      active_o     : out std_ulogic;

      dr_capture_i : in  std_ulogic;
      dr_shift_i   : in  std_ulogic;
      value_o      : out std_ulogic_vector(dr_len - 1 downto 0);
      value_i      : in  std_ulogic_vector(dr_len - 1 downto 0)
      );
  end component;

end package jtag;
