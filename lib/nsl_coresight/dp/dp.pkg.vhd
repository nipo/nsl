library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

-- Coresight SW-DP implementation, either self-clocked from SWCLK or oversampled.
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

  component swdp_sync is
    generic(
      idr : unsigned(31 downto 0) := X"0ba00477"
      );
    port(
      ref_clock_i : in std_ulogic;
      ref_reset_n_i : in std_ulogic;

      swd_i : in nsl_coresight.swd.swd_slave_i;
      swd_o : out nsl_coresight.swd.swd_slave_o;
      
      dap_i : in nsl_coresight.dapbus.dapbus_m_i;
      dap_o : out nsl_coresight.dapbus.dapbus_m_o;

      ctrl_o : out std_ulogic_vector(31 downto 0);
      stat_i : in std_ulogic_vector(31 downto 0);

      abort_o : out std_ulogic_vector(4 downto 0)
      );
  end component;

  type dp_tech_t is (
    DP_TECH_SWD,
    DP_TECH_JTAG,
    DP_TECH_DORMANT,
    DP_TECH_JTAG_SERIAL
    );

  type dp_state_t is (
    DP_UNSYNC,
    DP_RESET,
    DP_ACTIVE
    );

  component dp_monitor is
    port(
      reset_n_i: in std_ulogic := '1';

      dp_i : in nsl_coresight.swd.swd_slave_i;

      tech_o: out dp_tech_t;
      state_o: out dp_state_t
      );
  end component;
  
end dp;
