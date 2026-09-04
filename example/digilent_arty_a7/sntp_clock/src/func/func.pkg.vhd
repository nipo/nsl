library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_smi;

package func is

  component func_main is
    generic(
      clock_hz_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      l1_rx_i : in nsl_amba.axi4_stream.master_t;
      l1_rx_o : out nsl_amba.axi4_stream.slave_t;
      l1_tx_o : out nsl_amba.axi4_stream.master_t;
      l1_tx_i : in nsl_amba.axi4_stream.slave_t;

      smi_o : out nsl_smi.smi.smi_master_o;
      smi_i : in nsl_smi.smi.smi_master_i;

      -- Heartbeat, link up, DHCP lease, SNTP synchronized
      led_o : out std_ulogic_vector(0 to 3);

      -- Observation points
      link_up_o : out std_ulogic;
      dhcp_valid_o : out std_ulogic;
      sntp_valid_o : out std_ulogic;
      address_o : out unsigned(31 downto 0);
      ntp_server_o : out unsigned(31 downto 0);

      seconds_o : out unsigned(31 downto 0)
      );
  end component;

  component screen_text is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      link_up_i : in std_ulogic;
      dhcp_valid_i : in std_ulogic;
      sntp_valid_i : in std_ulogic;
      address_i : in unsigned(31 downto 0);
      ntp_server_i : in unsigned(31 downto 0);
      seconds_i : in unsigned(31 downto 0);

      -- Terminal text buffer write port
      row_o : out unsigned(2 downto 0);
      column_o : out unsigned(3 downto 0);
      write_o : out std_ulogic;
      character_o : out unsigned(7 downto 0);
      foreground_o : out unsigned(2 downto 0)
      );
  end component;

end package;
