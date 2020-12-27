library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_smi;

package master is

  type smi_op_t is (
    SMI_C45_ADDR,
    SMI_C45_WRITE,
    SMI_C45_READINC,
    SMI_C45_READ,
    SMI_C22_READ,
    SMI_C22_WRITE
    );
  
  component smi_master
    generic(
      clock_freq_c : natural := 150000000;
      mdc_freq_c : natural := 25000000
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      smi_o  : out nsl_smi.smi.smi_master_o;
      smi_i  : in  nsl_smi.smi.smi_master_i;
      
      cmd_valid_i : in std_ulogic;
      cmd_ready_o : out std_ulogic;
      cmd_op_i : in smi_op_t;
      -- clause 22 PHYAD, clause 45 PRTAD
      cmd_prtad_phyad_i : in unsigned(4 downto 0);
      -- clause 22 REGAD, clause 45 DEVAD
      cmd_devad_regad_i : in unsigned(4 downto 0);
      -- May be address for clause 45 ADDR_W
      cmd_data_addr_i : in std_ulogic_vector(15 downto 0);

      rsp_valid_o : out std_ulogic;
      rsp_ready_i : in std_ulogic;
      rsp_data_o : out std_ulogic_vector(15 downto 0);
      rsp_error_o : out std_ulogic
      );
  end component;

end package master;
