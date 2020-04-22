library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

package control_status is

  subtype control_status_reg is std_ulogic_vector(31 downto 0);
  type control_status_reg_array is array (natural range <>) of control_status_reg;

  constant CONTROL_STATUS_REG_WRITE: std_ulogic_vector(7 downto 0) := "0-------";
  constant CONTROL_STATUS_REG_READ : std_ulogic_vector(7 downto 0) := "1-------";
  
  component framed_control_status
    generic (
      config_count_c : integer range 1 to 128;
      status_count_c : integer range 1 to 128
      );
    port (
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;

      rsp_o   : out nsl_bnoc.framed.framed_req;
      rsp_i   : in nsl_bnoc.framed.framed_ack;

      config_o : out control_status_reg_array(config_count_c-1 downto 0);
      status_i : in  control_status_reg_array(status_count_c-1 downto 0) := (others => (others => '-'))
      );
  end component;

end package control_status;
