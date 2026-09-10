library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_clocking, nsl_amba, nsl_inet, nsl_data, nsl_mii,
  nsl_digilent, nsl_sipeed, gatecap_generated;
use nsl_amba.axi4_stream.all;
use nsl_mii.flit.all;
use nsl_sipeed.pmod_ethernet.all;
use nsl_inet.mac.all;
use nsl_inet.ipv4.all;
use nsl_inet.stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

-- IPv4 host over 10BASE-T without a Phy, on the ethernet PMOD.
--
-- The fabric MAU carries the wire, the turnkey IPv4 host carries the
-- stack: ARP, ICMP echo and DHCP.  The board acquires its address
-- through DHCP and answers pings.
--
-- A gatecap rack rides the UART: a control-status panel carries the
-- link and lease state plus frame counters along the receive and
-- transmit paths, and a logic analyzer samples the raw line.  Link
-- state is on the done LED, DHCP lease on the ready LED.
--
-- The line has no flow control: received frames go through a
-- store-and-forward fifo which also drops errored ones, and
-- transmitted frames go through a prefill buffer so the stack cannot
-- underrun the line.
entity boundary is
  port (
    clk_i: in std_ulogic;

    pmod_io: inout nsl_digilent.pmod.pmod_double_t;

    uart_tx_o: out std_ulogic;
    uart_rx_i: in std_ulogic;

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic
    );
end boundary;

architecture arch of boundary is

  constant clock_ext_hz_c: integer := 50000000;
  -- The MAU oversamples the line, and wants a multiple of 20 MHz.
  constant clock_line_hz_c: integer := 100000000;
  -- The stack closes timing well below the line clock, so it runs in
  -- its own domain and the two meet through dual-clock stream fifos.
  -- 10 Mb/s is one byte per 400 core cycles, so the board clock is
  -- plenty and saves a PLL.
  constant clock_core_hz_c: integer := clock_ext_hz_c;
  constant baudrate_c: integer := 1000000;

  constant cfg_c: config_t := stream_config(1);
  constant local_mac_c: mac48_t := from_hex("024e534c0042");
  constant udp_echo_port_c: integer := 1234;

  -- Address acquisition.  With use_dhcp_c cleared, the static
  -- addresses below are used instead and the lease ports read zero.
  constant use_dhcp_c: boolean := true;
  constant static_address_c: ipv4_t := to_ipv4(10, 0, 1, 88);
  constant static_netmask_c: ipv4_t := to_ipv4(255, 255, 254, 0);
  constant static_gateway_c: ipv4_t := to_ipv4(10, 0, 0, 1);

  signal clock_ext_s, clock_line_s, clock_core_s: std_ulogic;
  signal por_n_s, line_reset_n_s, reset_n_s: std_ulogic;
  signal probe_s: pmod_ethernet_probe_t;
  signal collision_s, late_collision_s, excessive_collision_s: std_ulogic;
  signal collision_core_s: std_ulogic_vector(2 downto 0);
  signal rx_raw_s, rx_core_s, rx_clean_s: bus_t;
  signal tx_s, tx_line_s, tx_prefilled_s: bus_t;
  signal rx_error_s: std_ulogic;
  signal to_app_s, from_app_s: master_vector(0 to 0);
  signal to_app_ack_s, from_app_ack_s: slave_vector(0 to 0);
  signal link_up_s, link_up_core_s, dhcp_valid_s, crs_s: std_ulogic;
  signal dhcp_address_s, dhcp_netmask_s, dhcp_router_s, dhcp_dns_s: ipv4_t;

  type regs_t is
  record
    -- Frames handed over by the MAU, frames surviving the error
    -- filter, and frames handed to the MAU.
    rx_frames: unsigned(15 downto 0);
    rx_clean: unsigned(15 downto 0);
    tx_frames: unsigned(15 downto 0);

    -- Collision strobes are counted in the core domain, so the
    -- counts are a sample of a line-domain event: exact enough to
    -- watch, not a protocol counter.
    collision_d: std_ulogic_vector(2 downto 0);
    collisions: unsigned(15 downto 0);
    late_collisions: unsigned(15 downto 0);
    excessive_collisions: unsigned(15 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  clk_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  por: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_ext_s,
      reset_n_o => por_n_s
      );

  line_pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clock_ext_hz_c,
      output_hz_c => clock_line_hz_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => por_n_s,
      clock_o => clock_line_s,
      locked_o => line_reset_n_s
      );

  clock_core_s <= clock_ext_s;

  reset_n_s <= line_reset_n_s;

  phy: nsl_sipeed.pmod_ethernet.pmod_ethernet_axi4_stream
    generic map(
      clock_i_hz_c => clock_line_hz_c
      )
    port map(
      clock_i => clock_line_s,
      reset_n_i => reset_n_s,

      pmod_io => pmod_io,

      rx_o => rx_raw_s.m,
      rx_i => rx_raw_s.s,

      tx_i => tx_prefilled_s.m,
      tx_o => tx_prefilled_s.s,

      link_up_o => link_up_s,
      polarity_inverted_o => open,
      crs_o => crs_s,
      col_o => open,
      collision_o => collision_s,
      late_collision_o => late_collision_s,
      excessive_collision_o => excessive_collision_s,

      probe_o => probe_s
      );

  -- Errored frames are flagged with the user bit; drop them before
  -- they reach the stack.
  rx_error_s <= user(axi4_flit_cfg, rx_core_s.m)(0);

  rx_cdc: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => axi4_flit_cfg,
      depth_c => 512,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => clock_line_s,
      clock_i(1) => clock_core_s,
      reset_n_i => reset_n_s,

      in_i => rx_raw_s.m,
      in_o => rx_raw_s.s,
      in_free_o => open,

      out_o => rx_core_s.m,
      out_i => rx_core_s.s,
      out_available_o => open
      );

  rx_cleaner: nsl_amba.stream_fifo.axi4_stream_fifo_clean
    generic map(
      config_c => axi4_flit_cfg,
      fifo_word_count_l2 => 11
      )
    port map(
      clock_i => clock_core_s,
      reset_n_i => reset_n_s,

      in_error_i => rx_error_s,
      in_i => rx_core_s.m,
      in_o => rx_core_s.s,

      out_o => rx_clean_s.m,
      out_i => rx_clean_s.s
      );

  host: nsl_inet.stream_host.stream_ipv4_host
    generic map(
      config_c => cfg_c,
      udp_port_c => (0 => udp_echo_port_c),
      dhcp_c => use_dhcp_c,
      clock_i_hz_c => clock_core_hz_c,
      hostname_c => "tang60k"
      )
    port map(
      clock_i => clock_core_s,
      reset_n_i => reset_n_s,

      local_hwaddr_i => local_mac_c,
      local_address_i => static_address_c,
      local_netmask_i => static_netmask_c,
      local_gateway_i => static_gateway_c,

      dhcp_address_o => dhcp_address_s,
      dhcp_netmask_o => dhcp_netmask_s,
      dhcp_router_o => dhcp_router_s,
      dhcp_dns_o => dhcp_dns_s,
      dhcp_valid_o => dhcp_valid_s,

      l1_header_i => null_byte_string,

      l1_rx_i => rx_clean_s.m,
      l1_rx_o => rx_clean_s.s,
      l1_tx_o => tx_s.m,
      l1_tx_i => tx_s.s,

      to_app_o => to_app_s,
      to_app_i => to_app_ack_s,
      from_app_i => from_app_s,
      from_app_o => from_app_ack_s
      );

  -- The UDP service port is a sink: it accepts and drops.  A
  -- loopback echo would need a fifo deep enough for a whole datagram,
  -- and a single-clock axi4_stream_fifo that deep corrupts every
  -- sixteenth byte on this device; a shallower one would head-of-line
  -- block the whole UDP receive path, DHCP included, on the first
  -- oversized datagram.
  to_app_ack_s(0) <= accept(cfg_c, true);
  from_app_s(0) <= transfer_defaults(cfg_c);

  tx_cdc: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => axi4_flit_cfg,
      depth_c => 512,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => clock_core_s,
      clock_i(1) => clock_line_s,
      reset_n_i => reset_n_s,

      in_i => tx_s.m,
      in_o => tx_s.s,
      in_free_o => open,

      out_o => tx_line_s.m,
      out_i => tx_line_s.s,
      out_available_o => open
      );

  tx_prefill: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
    generic map(
      config_c => axi4_flit_cfg,
      prefill_count_c => 12
      )
    port map(
      clock_i => clock_line_s,
      reset_n_i => reset_n_s,

      in_i => tx_line_s.m,
      in_o => tx_line_s.s,

      out_o => tx_prefilled_s.m,
      out_i => tx_prefilled_s.s
      );

  regs: process(clock_core_s, reset_n_s)
  begin
    if rising_edge(clock_core_s) then
      r <= rin;
    end if;
    if reset_n_s = '0' then
      r.rx_frames <= (others => '0');
      r.rx_clean <= (others => '0');
      r.tx_frames <= (others => '0');
      r.collisions <= (others => '0');
      r.late_collisions <= (others => '0');
      r.excessive_collisions <= (others => '0');
    end if;
  end process;

  transition: process(r, rx_core_s, rx_clean_s, tx_s, collision_core_s)
  begin
    rin <= r;

    rin.collision_d <= collision_core_s;
    if collision_core_s(0) = '1' and r.collision_d(0) = '0' then
      rin.collisions <= r.collisions + 1;
    end if;
    if collision_core_s(1) = '1' and r.collision_d(1) = '0' then
      rin.late_collisions <= r.late_collisions + 1;
    end if;
    if collision_core_s(2) = '1' and r.collision_d(2) = '0' then
      rin.excessive_collisions <= r.excessive_collisions + 1;
    end if;

    if is_valid(cfg_c, rx_core_s.m) and is_ready(cfg_c, rx_core_s.s)
      and is_last(cfg_c, rx_core_s.m) then
      rin.rx_frames <= r.rx_frames + 1;
    end if;

    if is_valid(cfg_c, rx_clean_s.m) and is_ready(cfg_c, rx_clean_s.s)
      and is_last(cfg_c, rx_clean_s.m) then
      rin.rx_clean <= r.rx_clean + 1;
    end if;

    if is_valid(cfg_c, tx_s.m) and is_ready(cfg_c, tx_s.s)
      and is_last(cfg_c, tx_s.m) then
      rin.tx_frames <= r.tx_frames + 1;
    end if;
  end process;

  collision_sync: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 3
      )
    port map(
      clock_i => clock_core_s,
      data_i(0) => collision_s,
      data_i(1) => late_collision_s,
      data_i(2) => excessive_collision_s,
      data_o => collision_core_s
      );

  link_sync: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 1
      )
    port map(
      clock_i => clock_core_s,
      data_i(0) => link_up_s,
      data_o(0) => link_up_core_s
      );

  observer: gatecap_generated.observer.observer_core
    generic map(
      baud_rate_c => baudrate_c,
      clock_frequency_c => clock_core_hz_c,
      burst_length_l2_c => 6
      )
    port map(
      reset_n_i => reset_n_s,

      uart_rx_i => uart_rx_i,
      uart_tx_o => uart_tx_o,

      line_sample_clock_i => clock_line_s,
      line_sample_reset_n_i => reset_n_s,
      line_sample_rx_i => probe_s.rx,
      line_sample_crs_i => crs_s,
      line_sample_tx_en_i => probe_s.tx_en,
      line_sample_tx_p_i => probe_s.tx_p,
      line_sample_link_up_i => link_up_s,

      panel_clock_i => clock_core_s,
      panel_reset_n_i => reset_n_s,
      panel_link_up_i => link_up_core_s,
      panel_dhcp_valid_i => dhcp_valid_s,
      panel_address_i => unsigned(from_be(dhcp_address_s)),
      panel_netmask_i => unsigned(from_be(dhcp_netmask_s)),
      panel_router_i => unsigned(from_be(dhcp_router_s)),
      panel_dns_i => unsigned(from_be(dhcp_dns_s)),
      panel_rx_frames_i => r.rx_frames,
      panel_rx_clean_i => r.rx_clean,
      panel_tx_frames_i => r.tx_frames,
      panel_collisions_i => r.collisions,
      panel_late_collisions_i => r.late_collisions,
      panel_excessive_collisions_i => r.excessive_collisions
      );

  done_led_o <= link_up_s;
  ready_led_o <= dhcp_valid_s;

end arch;
