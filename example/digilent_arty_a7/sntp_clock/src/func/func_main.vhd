library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data, nsl_inet, nsl_mii, nsl_smi, nsl_math,
  work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_math.int_ext.all;
use nsl_inet.mac.all;
use nsl_inet.ipv4.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.stream_udp.all;
use nsl_inet.stream_sntp.all;
use nsl_inet.stream_host.all;
use nsl_mii.link.all;
use nsl_mii.link_monitor.all;

entity func_main is
  generic(
    clock_hz_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    l1_rx_i : in master_t;
    l1_rx_o : out slave_t;
    l1_tx_o : out master_t;
    l1_tx_i : in slave_t;

    smi_o : out nsl_smi.smi.smi_master_o;
    smi_i : in nsl_smi.smi.smi_master_i;

    led_o : out std_ulogic_vector(0 to 3);

    link_up_o : out std_ulogic;
    dhcp_valid_o : out std_ulogic;
    sntp_valid_o : out std_ulogic;
    address_o : out unsigned(31 downto 0);
    ntp_server_o : out unsigned(31 downto 0);

    seconds_o : out unsigned(31 downto 0)
    );
end entity;

architecture beh of func_main is

  constant cfg_c : config_t := stream_config(1);
  constant local_mac_c : mac48_t := from_hex("02deadbeef4e");
  constant ipv4_zero_c : ipv4_t := to_ipv4(0, 0, 0, 0);

  -- Receive-side blocks ahead of the SNTP payload on a host with no
  -- layer-1 pre-header.
  constant sntp_blocks_c : integer_vector(0 to 2)
    := (l2_context_length_c, ip_context_length_c, udp_context_length_c);

  signal to_app_s, from_app_s : master_vector(0 to 0);
  signal to_app_ack_s, from_app_ack_s : slave_vector(0 to 0);

  signal dhcp_valid_s, sntp_valid_s, server_known_s : std_ulogic;
  signal ntp_server_s, address_s : ipv4_t;
  signal time_s : unsigned(63 downto 0);

  signal link_status_s : link_status_t;
  signal smi_cmd_s : nsl_bnoc.framed.framed_bus;
  signal smi_rsp_s : nsl_bnoc.framed.framed_bus;

  signal heartbeat_s : unsigned(26 downto 0);

begin

  host: nsl_inet.stream_host.stream_ipv4_host
    generic map(
      config_c => cfg_c,
      udp_port_c => (0 => sntp_port_c),
      dhcp_c => true,
      clock_i_hz_c => clock_hz_c,
      hostname_c => "arty"
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_hwaddr_i => local_mac_c,

      dhcp_address_o => address_s,
      dhcp_ntp_server_o => ntp_server_s,
      dhcp_valid_o => dhcp_valid_s,

      l1_header_i => null_byte_string,

      l1_rx_i => l1_rx_i,
      l1_rx_o => l1_rx_o,
      l1_tx_o => l1_tx_o,
      l1_tx_i => l1_tx_i,

      to_app_o => to_app_s,
      to_app_i => to_app_ack_s,
      from_app_i => from_app_s,
      from_app_o => from_app_ack_s
      );

  server_known_s <= '1' when dhcp_valid_s = '1' and ntp_server_s /= ipv4_zero_c
                    else '0';

  sntp: nsl_inet.stream_sntp.stream_sntp_client
    generic map(
      config_c => cfg_c,
      header_length_c => sntp_blocks_c,
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      server_i => ntp_server_s,
      server_valid_i => server_known_s,

      rx_i => to_app_s(0),
      rx_o => to_app_ack_s(0),
      tx_o => from_app_s(0),
      tx_i => from_app_ack_s(0),

      time_o => time_s,
      valid_o => sntp_valid_s
      );

  monitor: nsl_mii.link_monitor.link_monitor_smi
    generic map(
      clock_i_hz_c => clock_hz_c,
      phy_type_c => PHY_DP83xxx
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      phyad_i => to_unsigned(1, 5),
      link_status_o => link_status_s,

      cmd_o => smi_cmd_s.req,
      cmd_i => smi_cmd_s.ack,
      rsp_i => smi_rsp_s.req,
      rsp_o => smi_rsp_s.ack
      );

  smi: nsl_smi.transactor.smi_framed_transactor
    generic map(
      clock_freq_c => clock_hz_c,
      mdc_freq_c => 2500000
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      smi_o => smi_o,
      smi_i => smi_i,

      cmd_i => smi_cmd_s.req,
      cmd_o => smi_cmd_s.ack,
      rsp_o => smi_rsp_s.req,
      rsp_i => smi_rsp_s.ack
      );

  ticker: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      heartbeat_s <= heartbeat_s + 1;
    end if;

    if reset_n_i = '0' then
      heartbeat_s <= (others => '0');
    end if;
  end process;

  led_o(0) <= heartbeat_s(heartbeat_s'left);
  led_o(1) <= '1' when link_status_s.up else '0';
  led_o(2) <= dhcp_valid_s;
  led_o(3) <= sntp_valid_s;

  link_up_o <= '1' when link_status_s.up else '0';
  dhcp_valid_o <= dhcp_valid_s;
  sntp_valid_o <= sntp_valid_s;
  address_o <= from_be(address_s);
  ntp_server_o <= from_be(ntp_server_s);

  seconds_o <= (time_s(63 downto 32) - x"83aa7e80") when sntp_valid_s = '1' else (31 downto 0 => '0');

end architecture;
