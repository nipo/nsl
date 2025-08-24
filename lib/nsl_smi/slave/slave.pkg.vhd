library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_smi, nsl_amba;

package slave is

  type smi_reg_array_t is array (natural range<>) of unsigned(15 downto 0);
  
  component smi_c22_slave_axi_master is
    generic (
      phy_addr_c      : unsigned(4 downto 0);
      config_c        : nsl_amba.axi4_mm.config_t
      );
    port (
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      smi_i           : in nsl_smi.smi.smi_slave_i;
      smi_o           : out nsl_smi.smi.smi_slave_o;

      regmap_i        : in nsl_amba.axi4_mm.slave_t;
      regmap_o        : out nsl_amba.axi4_mm.master_t
      );
  end component;

  component smi_c22_slave_regmap is
    generic (
      phy_addr_c: unsigned(4 downto 0);
      reg_count_c: integer := 16
      );
    port (
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      smi_i           : in nsl_smi.smi.smi_slave_i;
      smi_o           : out nsl_smi.smi.smi_slave_o;

      register_i     : in smi_reg_array_t(0 to reg_count_c-1);
      register_o     : out smi_reg_array_t(0 to reg_count_c-1)
      );
  end component smi_c22_slave_regmap;

end package;
