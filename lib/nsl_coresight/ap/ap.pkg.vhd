library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_amba;

-- Coresight Access Port implemetations
package ap is

  component ap_axi4_lite is
    generic(
      -- This manufacturer ID (Continuation 3, id 0x00) is an
      -- undefined and reserved value in JEP106. If you want this
      -- component to be detected as ARM's MEM-AP, set IDR to
      -- x"04770004".
      idr : unsigned(31 downto 0) := X"03000004";
      config_c : nsl_amba.axi4_mm.config_t;
      rom_base : unsigned(31 downto 0)
      );
    port(
      clk_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      dbgen_i : in std_ulogic;
      spiden_i : in std_ulogic;

      dap_i : in nsl_coresight.dapbus.dapbus_m_o;
      dap_o : out nsl_coresight.dapbus.dapbus_m_i;

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in  nsl_amba.axi4_mm.slave_t
      );
  end component;
  
end package ap;
