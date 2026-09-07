library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_smi, nsl_dvi;
use nsl_dvi.terminal.all;

package func is

  -- Label screen layout, one full-width label per row on a 16x8
  -- terminal.  Color port entries:
  constant screen_color_background_c : natural := 0;
  constant screen_color_title_c : natural := 1;
  constant screen_color_value_c : natural := 2;
  constant screen_color_link_c : natural := 3;
  constant screen_color_sntp_c : natural := 4;
  constant screen_color_count_c : natural := 5;

  constant screen_labels_c : label_vector(0 to 7) := (
    text_label(0, 0, 16, screen_color_title_c, screen_color_background_c),
    text_label(1, 0, 16, screen_color_link_c, screen_color_background_c),
    text_label(2, 0, 16, screen_color_title_c, screen_color_background_c),
    text_label(3, 0, 16, screen_color_value_c, screen_color_background_c),
    text_label(4, 0, 16, screen_color_title_c, screen_color_background_c),
    text_label(5, 0, 16, screen_color_value_c, screen_color_background_c),
    text_label(6, 0, 16, screen_color_title_c, screen_color_background_c),
    text_label(7, 0, 16, screen_color_sntp_c, screen_color_background_c)
    );

  constant screen_text_length_c : natural := labels_text_length(screen_labels_c);

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

      -- Label screen contents, laid out as screen_labels_c
      text_o : out string(1 to screen_text_length_c);
      colors_o : out label_color_vector(0 to screen_color_count_c-1)
      );
  end component;

end package;
