library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

package dp is

  component swdp is
    generic(
      idr : unsigned(31 downto 0) := X"0ba00477"
      );
    port(
      swd_i : in nsl_coresight.swd.swd_slave_i;
      swd_o : out nsl_coresight.swd.swd_slave_o;
      
      dap_i : in nsl_coresight.dapbus.dapbus_m_i;
      dap_o : out nsl_coresight.dapbus.dapbus_m_o;

      ctrl_o : out std_ulogic_vector(31 downto 0);
      stat_i : in std_ulogic_vector(31 downto 0);

      abort_o : out std_ulogic_vector(4 downto 0)
      );
  end component;

end dp;
