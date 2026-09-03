library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_inet, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_inet.mac.all;
use nsl_inet.ipv4.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.stream_udp.all;
use work.stream_host.all;

entity stream_ipv4_host is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    udp_port_c : integer_vector;
    ttl_c : integer range 0 to 255 := 64;
    cache_count_l2_c : natural := 3;
    timeout_c : natural := 125000000;
    retry_count_c : natural := 3;
    dhcp_c : boolean := false;
    clock_i_hz_c : natural := 125000000;
    hostname_c : string := ""
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_hwaddr_i : in mac48_t;
    local_address_i : in ipv4_t := to_ipv4(0, 0, 0, 0);

    dhcp_address_o : out ipv4_t;
    dhcp_netmask_o : out ipv4_t;
    dhcp_router_o : out ipv4_t;
    dhcp_dns_o : out ipv4_t;
    dhcp_valid_o : out std_ulogic;

    l1_header_i : in byte_string;

    l1_rx_i : in master_t;
    l1_rx_o : out slave_t;
    l1_tx_o : out master_t;
    l1_tx_i : in slave_t;

    to_app_o : out master_vector(0 to udp_port_c'length-1);
    to_app_i : in slave_vector(0 to udp_port_c'length-1);
    from_app_i : in master_vector(0 to udp_port_c'length-1);
    from_app_o : out slave_vector(0 to udp_port_c'length-1)
    );
end entity;

architecture beh of stream_ipv4_host is

  constant app_count_c : natural := udp_port_c'length;

  constant hdr_l2_c : integer_vector
    := header_length_c & l2_context_length_c;
  constant hdr_l3_c : integer_vector
    := hdr_l2_c & ip_context_length_c;

  signal local_address_s : ipv4_t;

  signal mac_to_eth_s, eth_to_mac_s : bus_t;
  signal eth_to_ip_s, ip_to_eth_s : bus_t;
  signal eth_to_arp_s, arp_to_eth_s : bus_t;
  signal ip_to_icmp_s, icmp_to_ip_s : bus_t;
  signal ip_to_udp_s, udp_to_ip_s : bus_t;
  signal arp_query_s, arp_response_s : bus_t;

begin

  assert udp_port_c'length >= 1
    report "At least one UDP port is required"
    severity failure;

  mac_rx: nsl_inet.stream_mac.stream_mac_receiver
    generic map(
      config_c => config_c,
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_i => l1_rx_i,
      in_o => l1_rx_o,
      out_o => mac_to_eth_s.m,
      out_i => mac_to_eth_s.s
      );

  mac_tx: nsl_inet.stream_mac.stream_mac_transmitter
    generic map(
      config_c => config_c,
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_i => eth_to_mac_s.m,
      in_o => eth_to_mac_s.s,
      out_o => l1_tx_o,
      out_i => l1_tx_i
      );

  eth: nsl_inet.stream_ethernet.stream_ethernet_layer
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      ethertype_c => (16#0800#, 16#0806#)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_hwaddr_i,

      to_l3_o(0) => eth_to_ip_s.m,
      to_l3_o(1) => eth_to_arp_s.m,
      to_l3_i(0) => eth_to_ip_s.s,
      to_l3_i(1) => eth_to_arp_s.s,
      from_l3_i(0) => ip_to_eth_s.m,
      from_l3_i(1) => arp_to_eth_s.m,
      from_l3_o(0) => ip_to_eth_s.s,
      from_l3_o(1) => arp_to_eth_s.s,

      to_l1_o => eth_to_mac_s.m,
      to_l1_i => eth_to_mac_s.s,
      from_l1_i => mac_to_eth_s.m,
      from_l1_o => mac_to_eth_s.s
      );

  ip: nsl_inet.stream_ipv4.stream_ipv4_layer
    generic map(
      config_c => config_c,
      header_length_c => hdr_l2_c,
      ip_proto_c => (ip_proto_icmp, ip_proto_udp),
      ttl_c => ttl_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_address_s,

      to_l4_o(0) => ip_to_icmp_s.m,
      to_l4_o(1) => ip_to_udp_s.m,
      to_l4_i(0) => ip_to_icmp_s.s,
      to_l4_i(1) => ip_to_udp_s.s,
      from_l4_i(0) => icmp_to_ip_s.m,
      from_l4_i(1) => udp_to_ip_s.m,
      from_l4_o(0) => icmp_to_ip_s.s,
      from_l4_o(1) => udp_to_ip_s.s,

      to_l3_o => ip_to_eth_s.m,
      to_l3_i => ip_to_eth_s.s,
      from_l3_i => eth_to_ip_s.m,
      from_l3_o => eth_to_ip_s.s
      );

  icmp: nsl_inet.stream_ipv4.stream_ipv4_icmp_echo
    generic map(
      config_c => config_c,
      header_length_c => hdr_l3_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => ip_to_icmp_s.m,
      in_o => ip_to_icmp_s.s,

      out_o => icmp_to_ip_s.m,
      out_i => icmp_to_ip_s.s
      );

  arp: nsl_inet.stream_arp.stream_arp_resolver
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      cache_count_l2_c => cache_count_l2_c,
      timeout_c => timeout_c,
      retry_count_c => retry_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_hwaddr_i => local_hwaddr_i,
      local_address_i => local_address_s,

      l1_header_i => l1_header_i,

      from_l2_i => eth_to_arp_s.m,
      from_l2_o => eth_to_arp_s.s,
      to_l2_o => arp_to_eth_s.m,
      to_l2_i => arp_to_eth_s.s,

      query_i => arp_query_s.m,
      query_o => arp_query_s.s,

      response_o => arp_response_s.m,
      response_i => arp_response_s.s
      );

  -- The UDP layer, the resolver entries and their arbiter are sized
  -- by the DHCP pipe, so each branch instantiates its own cluster,
  -- with the application streams associated directly: a copy through
  -- an intermediate signal would skew the two sides of a handshake
  -- by a delta cycle.
  no_dhcp: if not dhcp_c generate
    signal entry_to_udp_m_s : master_vector(0 to app_count_c-1);
    signal entry_to_udp_a_s : slave_vector(0 to app_count_c-1);
    signal query_m_s, response_m_s : master_vector(0 to app_count_c-1);
    signal query_a_s, response_a_s : slave_vector(0 to app_count_c-1);
  begin
    local_address_s <= local_address_i;
    dhcp_address_o <= to_ipv4(0, 0, 0, 0);
    dhcp_netmask_o <= to_ipv4(0, 0, 0, 0);
    dhcp_router_o <= to_ipv4(0, 0, 0, 0);
    dhcp_dns_o <= to_ipv4(0, 0, 0, 0);
    dhcp_valid_o <= '0';

    udp: nsl_inet.stream_udp.stream_udp_layer
      generic map(
        config_c => config_c,
        header_length_c => hdr_l3_c,
        udp_port_c => udp_port_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        local_address_i => local_address_s,

        to_app_o => to_app_o,
        to_app_i => to_app_i,
        from_app_i => entry_to_udp_m_s,
        from_app_o => entry_to_udp_a_s,

        to_l4_o => udp_to_ip_s.m,
        to_l4_i => udp_to_ip_s.s,
        from_l4_i => ip_to_udp_s.m,
        from_l4_o => ip_to_udp_s.s
        );

    entries: for i in 0 to app_count_c-1 generate
    begin
      entry: nsl_inet.stream_resolver.stream_resolver_entry
        generic map(
          config_c => config_c,
          query_length_c => ip_context_length_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => from_app_i(i),
          in_o => from_app_o(i),

          query_o => query_m_s(i),
          query_i => query_a_s(i),
          response_i => response_m_s(i),
          response_o => response_a_s(i),

          out_o => entry_to_udp_m_s(i),
          out_i => entry_to_udp_a_s(i)
          );
    end generate;

    arbiter: nsl_inet.stream_resolver.stream_resolver_arbiter
      generic map(
        config_c => config_c,
        source_count_c => app_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        query_i => query_m_s,
        query_o => query_a_s,
        response_o => response_m_s,
        response_i => response_a_s,

        resolver_query_o => arp_query_s.m,
        resolver_query_i => arp_query_s.s,
        resolver_response_i => arp_response_s.m,
        resolver_response_o => arp_response_s.s
        );
  end generate;

  has_dhcp: if dhcp_c generate
    constant port_count_c : natural := app_count_c + 1;
    constant narrow_c : config_t := stream_config(1);
    constant rx_blocks_c : integer_vector
      := hdr_l3_c & udp_context_length_c;
    constant tx_blocks_c : integer_vector(0 to 1)
      := (ip_context_length_c, udp_context_length_c);
    signal entry_to_udp_m_s : master_vector(0 to port_count_c-1);
    signal entry_to_udp_a_s : slave_vector(0 to port_count_c-1);
    signal to_app_m_s : master_vector(0 to port_count_c-1);
    signal to_app_a_s : slave_vector(0 to port_count_c-1);
    signal query_m_s, response_m_s : master_vector(0 to port_count_c-1);
    signal query_a_s, response_a_s : slave_vector(0 to port_count_c-1);
    signal dhcp_to_entry_s : bus_t;
    signal rx_narrow_s, tx_narrow_s : bus_t;
    signal address_s : ipv4_t;
  begin
    local_address_s <= address_s;
    dhcp_address_o <= address_s;

    udp: nsl_inet.stream_udp.stream_udp_layer
      generic map(
        config_c => config_c,
        header_length_c => hdr_l3_c,
        udp_port_c => udp_port_c
          & nsl_inet.stream_dhcp.dhcp_client_port_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        local_address_i => local_address_s,

        to_app_o => to_app_m_s,
        to_app_i => to_app_a_s,
        from_app_i => entry_to_udp_m_s,
        from_app_o => entry_to_udp_a_s,

        to_l4_o => udp_to_ip_s.m,
        to_l4_i => udp_to_ip_s.s,
        from_l4_i => ip_to_udp_s.m,
        from_l4_o => ip_to_udp_s.s
        );

    -- Splitting a vector formal takes locally static indices, which
    -- app_count_c is not, and copy assignments would skew the
    -- handshake pair by a delta cycle, so each application pipe goes
    -- through a register slice.
    app_slices: for i in 0 to app_count_c-1 generate
    begin
      slice: nsl_amba.stream_fifo.axi4_stream_slice
        generic map(
          config_c => config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => to_app_m_s(i),
          in_o => to_app_a_s(i),

          out_o => to_app_o(i),
          out_i => to_app_i(i)
          );
    end generate;

    entries: for i in 0 to app_count_c-1 generate
    begin
      entry: nsl_inet.stream_resolver.stream_resolver_entry
        generic map(
          config_c => config_c,
          query_length_c => ip_context_length_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => from_app_i(i),
          in_o => from_app_o(i),

          query_o => query_m_s(i),
          query_i => query_a_s(i),
          response_i => response_m_s(i),
          response_o => response_a_s(i),

          out_o => entry_to_udp_m_s(i),
          out_i => entry_to_udp_a_s(i)
          );
    end generate;

    dhcp_entry: nsl_inet.stream_resolver.stream_resolver_entry
      generic map(
        config_c => config_c,
        query_length_c => ip_context_length_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => dhcp_to_entry_s.m,
        in_o => dhcp_to_entry_s.s,

        query_o => query_m_s(app_count_c),
        query_i => query_a_s(app_count_c),
        response_i => response_m_s(app_count_c),
        response_o => response_a_s(app_count_c),

        out_o => entry_to_udp_m_s(app_count_c),
        out_i => entry_to_udp_a_s(app_count_c)
        );

    arbiter: nsl_inet.stream_resolver.stream_resolver_arbiter
      generic map(
        config_c => config_c,
        source_count_c => port_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        query_i => query_m_s,
        query_o => query_a_s,
        response_o => response_m_s,
        response_i => response_a_s,

        resolver_query_o => arp_query_s.m,
        resolver_query_i => arp_query_s.s,
        resolver_response_i => arp_response_s.m,
        resolver_response_o => arp_response_s.s
        );

    rx_resize: nsl_inet.stream.stream_block_resizer
      generic map(
        in_config_c => config_c,
        out_config_c => narrow_c,
        header_length_c => rx_blocks_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => to_app_m_s(app_count_c),
        in_o => to_app_a_s(app_count_c),

        out_o => rx_narrow_s.m,
        out_i => rx_narrow_s.s
        );

    tx_resize: nsl_inet.stream.stream_block_resizer
      generic map(
        in_config_c => narrow_c,
        out_config_c => config_c,
        header_length_c => tx_blocks_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => tx_narrow_s.m,
        in_o => tx_narrow_s.s,

        out_o => dhcp_to_entry_s.m,
        out_i => dhcp_to_entry_s.s
        );

    client: nsl_inet.stream_dhcp.stream_dhcp_client
      generic map(
        config_c => narrow_c,
        header_length_c => rx_blocks_c,
        clock_i_hz_c => clock_i_hz_c,
        hostname_c => hostname_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        hwaddr_i => local_hwaddr_i,

        rx_i => rx_narrow_s.m,
        rx_o => rx_narrow_s.s,
        tx_o => tx_narrow_s.m,
        tx_i => tx_narrow_s.s,

        address_o => address_s,
        netmask_o => dhcp_netmask_o,
        router_o => dhcp_router_o,
        dns_o => dhcp_dns_o,
        valid_o => dhcp_valid_o
        );
  end generate;

end architecture;
