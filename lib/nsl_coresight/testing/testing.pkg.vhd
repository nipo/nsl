library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

package testing is

  component swdap
    generic(
      idr: unsigned(31 downto 0) := X"2ba01477"
      );
    port (
      p_swd_c : out nsl_coresight.swd.swd_slave_o;
      p_swd_s : in nsl_coresight.swd.swd_slave_i;
      p_swd_resetn : out std_ulogic;

      p_ap_ready : in std_ulogic;

      p_ap_sel : out unsigned(7 downto 0);

      p_ap_a : out unsigned(5 downto 0);

      p_ap_rdata : in unsigned(31 downto 0);
      p_ap_rok : in std_logic;
      p_ap_ren : out std_logic;
      
      p_ap_wdata : out unsigned(31 downto 0);
      p_ap_wen : out std_logic
      );
  end component;

  component ap_sim
    port (
      p_clk : in std_ulogic;
      p_resetn : in std_ulogic;

      p_ready : out std_ulogic;

      p_ap : in unsigned(7 downto 0);

      p_a : in unsigned(5 downto 0);

      p_rdata : out unsigned(31 downto 0);
      p_rok : out std_logic;
      p_ren : in std_logic;

      p_wdata : in unsigned(31 downto 0);
      p_wen : in std_logic
      );
  end component;

end package testing;
