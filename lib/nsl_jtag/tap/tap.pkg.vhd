library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag;

package tap is
  
  component tap_controller is
    port(
      tck_i  : in  std_ulogic;
      tms_i  : in  std_ulogic;
      trst_i : in  std_ulogic := '1';

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

  component tap_port is
    generic(
      ir_len : natural
      );
    port(
      jtag_i : in  nsl_jtag.jtag.jtag_tap_i := nsl_jtag.jtag.jtag_tap_i_default;
      jtag_o : out  nsl_jtag.jtag.jtag_tap_o;

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

  component tap_dr is
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

end package tap;
