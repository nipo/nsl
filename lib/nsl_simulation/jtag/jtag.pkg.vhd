library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jtag is

  constant max_reg_count_c : positive := 4;

  signal reg_sel_g: integer range -1 to max_reg_count_c-1;
  signal reg_tdo_g: std_logic_vector(0 to max_reg_count_c-1);
  signal tck_g: std_ulogic;
  signal tlr_g: std_ulogic;
  signal rti_g: std_ulogic;
  signal tdi_g: std_ulogic;
  signal dr_capture_g: std_ulogic;
  signal dr_shift_g: std_ulogic;
  signal dr_update_g: std_ulogic;
  
  component jtag_sim_tap is
    generic(
      idcode_c : std_ulogic_vector(31 downto 0);
      idcode_instruction_c : std_ulogic_vector;
      user0_instruction_c : std_ulogic_vector
      );
    port(
      tck_i  : in  std_ulogic;
      tms_i  : in  std_ulogic;
      tdi_i  : in  std_ulogic;
      tdo_o  : out std_ulogic
      );
  end component;

  component jtag_sim_reg is
    generic(
      index_c : natural
      );
    port(
      tck_o     : out std_ulogic;
      tlr_o : out std_ulogic;
      selected_o: out std_ulogic;
      capture_o : out std_ulogic;
      shift_o   : out std_ulogic;
      update_o  : out std_ulogic;
      run_o  : out std_ulogic;
      tdi_o     : out std_ulogic;
      tdo_i     : in  std_ulogic
      );
  end component;

end package jtag;
