library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

package aximm is
  
  component axi4_lite_a32_d32_slave is
    generic (
      addr_size : natural range 3 to 32
      );
    port (
      aclk: in std_ulogic;
      aresetn: in std_ulogic := '1';

      p_axi_ms: in signalling.axi4_lite.a32_d32_ms;
      p_axi_sm: out signalling.axi4_lite.a32_d32_sm;

      p_addr : out std_ulogic_vector(addr_size-1 downto 2);

      p_w_data : out std_ulogic_vector(31 downto 0);
      p_w_mask : out std_ulogic_vector(3 downto 0);
      p_w_ready : in std_ulogic := '1';
      p_w_valid : out std_ulogic;

      p_r_data : in std_ulogic_vector(31 downto 0);
      p_r_ready : out std_ulogic;
      p_r_valid : in std_ulogic := '1'
      );
  end component;

end package aximm;
