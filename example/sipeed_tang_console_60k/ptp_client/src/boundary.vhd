library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_amba, nsl_inet, nsl_data, nsl_mii, nsl_math,
  nsl_time, nsl_ptp, nsl_video, nsl_color, nsl_indication, nsl_icesugar,
  nsl_digilent, nsl_sipeed, nsl_usb, gatecap_generated, work;
use nsl_amba.axi4_stream.all;
use nsl_mii.flit.all;
use nsl_mii.timestamping.all;
use nsl_sipeed.pmod_ethernet.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_math.fixed.all;
use nsl_time.timestamp.all;
use nsl_time.discipline.all;
use nsl_ptp.ptp.all;
use nsl_ptp.stream_l2.all;
use nsl_color.rgb.all;
use nsl_video.terminal.all;
use work.screen.all;

-- PTP slave over 10BASE-T without a Phy, on the ethernet PMOD.
--
-- An ordinary clock slave, layer-2 transport, end-to-end delay,
-- tracking the first master it hears.  Its time base is a counter
-- steered by increment: the servo correction changes the amount of
-- nanoseconds added per cycle, a large offset steps it.
--
-- The line domain holds everything that must be exact in time: the
-- MAU, whose SFD strobes are the timestamp points, the timestamping
-- shims, the time base and the capture register files.  The strobes
-- and the time base being on the same clock, captures are sampled
-- without any resynchronization.  The core domain holds the stack,
-- the protocol engine, the servo and the status screen.
--
-- Status shows on an LCD on J7, a pulse per second on A21 while
-- locked, link on the done LED, lock on the ready LED.  A gatecap
-- rack is a Full Speed device on the board's USB2 connector.
entity boundary is
  generic(
    -- Delay asymmetry of the measurement, in nanoseconds: the
    -- master-to-slave delay minus the slave-to-master delay as the
    -- timestamps see them, cable and both ends' timestamp latencies
    -- included.  Half of it biases the measured offset, and is taken
    -- off before the servo.  A slave pulse lagging the master's by d
    -- calls for 2 * d more.
    asymmetry_ns_c : integer := 0;
    -- TAI minus UTC, in seconds, for display only.
    utc_offset_c : natural := 37;
    display_utc_c : boolean := false;
    -- Ticker fires this early before the second boundary, to absorb
    -- the ticker registers and the output register.
    pps_output_lead_ns_c : natural := 30;
    domain_c : natural := 0
    );
  port (
    clk_i: in std_ulogic;

    j6_io: inout nsl_digilent.pmod.pmod_double_t;
    j7_io: inout nsl_digilent.pmod.pmod_double_t;

    pps_o: out std_ulogic;

    -- The board's USB2 connector, used at full speed.  The pins only
    -- the high speed phy would use are left floating.
    usb_dp_io: inout std_logic;
    usb_dn_io: inout std_logic;
    usb_dp_pullup_io: inout std_logic;
    usb_unused_io: inout std_logic_vector(0 to 5);

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic
    );
end boundary;

architecture arch of boundary is

  constant clock_ext_hz_c: integer := 50000000;
  -- The MAU oversamples the line, and wants a multiple of 20 MHz.
  -- This is also the time base clock: its period is the timestamp
  -- quantum.
  constant clock_line_hz_c: integer := 100000000;
  constant clock_core_hz_c: integer := clock_ext_hz_c;
  -- Reference clock of the Full Speed phy, and the rack's own clock.
  constant clock_usb_hz_c: integer := 60000000;

  constant pll_config_c: nsl_clocking.pll.pll_config_t
    := nsl_clocking.pll.pll_config(
      input_hz => clock_ext_hz_c,
      o0 => nsl_clocking.pll.pll_output(clock_line_hz_c),
      o1 => nsl_clocking.pll.pll_output(clock_usb_hz_c));

  signal clock_ext_s, clock_line_s, clock_core_s: std_ulogic;
  signal por_n_s, pll_locked_s: std_ulogic;
  signal core_reset_n_s, line_reset_n_s: std_ulogic;
  signal clock_usb_s, usb_reset_n_s: std_ulogic;

  -- Line state the instrumentation samples in the line domain.
  signal probe_s: pmod_ethernet_probe_t;
  signal link_up_s, crs_s: std_ulogic;

  -- Protocol and servo state, in the core domain, for the screen and
  -- the instrumentation panel.
  type status_t is
  record
    link_up: std_ulogic;
    locked: std_ulogic;
    second: unsigned(31 downto 0);
    -- Measured offset, asymmetry corrected, as the servo takes it.
    offset: timestamp_nanosecond_offset_t;
    path_delay: timestamp_nanosecond_offset_t;
    freq_ppb: frequency_ppb_t;
    syncs: unsigned(15 downto 0);
    steps: unsigned(15 downto 0);
    -- Frames handed over by the MAU, frames handed to the MAU, and
    -- transmit timestamps delivered to the protocol engine.
    rx_frames: unsigned(15 downto 0);
    tx_frames: unsigned(15 downto 0);
    tx_stamps: unsigned(15 downto 0);
  end record;

  signal status_s: status_t;

begin

  assert abs(asymmetry_ns_c) < 1000000
    report "Asymmetry is out of any plausible range"
    severity failure;

  clk_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  por: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_ext_s,
      reset_n_o => por_n_s
      );

  -- Outputs are bound to scalar signals one by one: synthesis keeps
  -- their names on the nets the timing constraints point at.
  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => por_n_s,
      clock_o(0) => clock_line_s,
      clock_o(1) => clock_usb_s,
      locked_o => pll_locked_s
      );

  clock_core_s <= clock_ext_s;

  core_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_core_s,
      data_i => pll_locked_s,
      data_o => core_reset_n_s
      );

  usb_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_usb_s,
      data_i => pll_locked_s,
      data_o => usb_reset_n_s
      );

  line_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_line_s,
      data_i => core_reset_n_s,
      data_o => line_reset_n_s
      );

  ------------------------------------------------------------------
  -- Ethernet and PTP: the MAU and its timestamping in the line
  -- domain, the stack, the protocol engine and the servo in the core
  -- domain, the disciplined time base and its pulse per second back
  -- in the line domain.
  ethernet_ptp: block is
    constant cfg_c: config_t := stream_config(1);
    constant hdr_c: integer_vector(0 to 0) := (0 => tag_length_c);
    constant blocks_c: integer_vector(0 to 1) := (tag_length_c, l2_context_length_c);
    constant groups_c: mac48_vector(0 to 0) := (0 => ptp_multicast_addr_c);

    constant local_mac_c: mac48_t := from_hex("0221cafe7c00");
    constant identity_c: byte_string(0 to 7) := from_hex("0221cafeff7c0000");

    -- The receive path holds a whole frame in its error filter before
    -- the protocol engine claims the frame's capture register: sixteen
    -- registers leave room for a burst of short frames in between.
    constant rx_id_bits_c: natural := 4;

    constant offset_correction_c: integer := asymmetry_ns_c / 2;

    -- About 10 ms of visible pulse.
    constant pps_stretch_c: natural := 2 ** 20 - 1;

    -- Line domain
    signal rx_sfd_s, tx_sfd_s: std_ulogic;
    signal rx_raw_s, rx_tagged_s, tx_line_s, tx_stripped_s, tx_prefilled_s: bus_t;
    signal rx_stamp_s, tx_stamp_s: std_ulogic;
    signal rx_stamp_id_s, tx_stamp_id_s: tag_id_t;
    signal time_s, step_time_s: timestamp_t;
    signal step_time_set_s: std_ulogic;
    signal inc_s: ufixed(4 downto -26);
    signal pps_tick_s, locked_line_s: std_ulogic;

    -- Read across domains, see nsl_mii.timestamping
    signal rx_capture_time_s, tx_capture_time_s: timestamp_t;

    -- Core domain
    signal rx_core_s, rx_clean_s, tx_s: bus_t;
    signal eth_to_ptp_s, ptp_to_eth_s, mac_to_eth_s: bus_t;
    signal rx_error_s: std_ulogic;
    signal capture_id_s: tag_id_t;
    signal tx_done_s: std_ulogic;
    signal offset_s, path_delay_s: timestamp_nanosecond_offset_t;
    signal offset_valid_s: std_ulogic;
    signal step_s, step_sync_s: timestamp_t;
    signal step_valid_s, locked_s: std_ulogic;
    signal freq_ppb_s: frequency_ppb_t;
    signal link_up_core_s: std_ulogic;
    signal second_core_s: std_ulogic_vector(31 downto 0);

    type line_regs_t is
    record
      second: timestamp_second_t;
      pps: std_ulogic;
      pps_stretch: natural range 0 to pps_stretch_c;
    end record;

    signal l, lin: line_regs_t;

    type regs_t is
    record
      -- Measurement handed to the servo, asymmetry corrected.
      offset: timestamp_nanosecond_offset_t;
      offset_valid: std_ulogic;

      syncs: unsigned(15 downto 0);
      steps: unsigned(15 downto 0);
      rx_frames: unsigned(15 downto 0);
      tx_frames: unsigned(15 downto 0);
      tx_stamps: unsigned(15 downto 0);
    end record;

    signal r, rin: regs_t;

  begin

    ----------------------------------------------------------------
    -- Line domain

    phy: nsl_sipeed.pmod_ethernet.pmod_ethernet_axi4_stream
      generic map(
        clock_i_hz_c => clock_line_hz_c
        )
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        pmod_io => j6_io,

        rx_o => rx_raw_s.m,
        rx_i => rx_raw_s.s,

        tx_i => tx_prefilled_s.m,
        tx_o => tx_prefilled_s.s,

        link_up_o => link_up_s,
        polarity_inverted_o => open,
        crs_o => crs_s,
        col_o => open,
        collision_o => open,
        late_collision_o => open,
        excessive_collision_o => open,

        tx_sfd_o => tx_sfd_s,
        rx_sfd_o => rx_sfd_s,

        probe_o => probe_s
        );

    rx_tagger: nsl_mii.timestamping.timestamping_rx_tagger
      generic map(
        config_c => axi4_flit_cfg,
        id_bits_c => rx_id_bits_c
        )
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        sfd_i => rx_sfd_s,
        sfd_o => rx_stamp_s,
        id_o => rx_stamp_id_s,

        in_i => rx_raw_s.m,
        in_o => rx_raw_s.s,
        out_o => rx_tagged_s.m,
        out_i => rx_tagged_s.s
        );

    rx_capture: nsl_time.capture.timestamp_capture
      generic map(
        id_bits_c => rx_id_bits_c
        )
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        timestamp_i => time_s,
        strobe_i => rx_stamp_s,
        id_i => rx_stamp_id_s,

        read_id_i => capture_id_s,
        read_timestamp_o => rx_capture_time_s
        );

    -- The strober sits before the prefill buffer: its tag queue spans
    -- the frames held in between, and every frame enters it with its
    -- tag block.
    tx_strober: nsl_mii.timestamping.timestamping_tx_strober
      generic map(
        config_c => axi4_flit_cfg
        )
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        sfd_i => tx_sfd_s,
        strobe_o => tx_stamp_s,
        id_o => tx_stamp_id_s,

        in_i => tx_line_s.m,
        in_o => tx_line_s.s,
        out_o => tx_stripped_s.m,
        out_i => tx_stripped_s.s
        );

    tx_prefill: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
      generic map(
        config_c => axi4_flit_cfg,
        prefill_count_c => 12
        )
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        in_i => tx_stripped_s.m,
        in_o => tx_stripped_s.s,

        out_o => tx_prefilled_s.m,
        out_i => tx_prefilled_s.s
        );

    tx_capture: nsl_time.capture.timestamp_capture
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        timestamp_i => time_s,
        strobe_i => tx_stamp_s,
        id_i => tx_stamp_id_s,

        read_id_i => ptp_tx_tag_id_c,
        read_timestamp_o => tx_capture_time_s
        );

    -- Only the completion crosses: by the time it reaches the core
    -- domain, the capture register written the cycle after the strobe
    -- has long settled.
    tx_done_resync: nsl_mii.timestamping.timestamping_sideband_resync
      port map(
        reset_n_i => core_reset_n_s,

        a_clock_i => clock_line_s,
        a_strobe_i => tx_stamp_s,
        a_id_i => tx_stamp_id_s,
        a_done_o => open,

        b_clock_i => clock_core_s,
        b_strobe_o => tx_done_s,
        b_id_o => open
        );

    -- Frequency correction and steps are commands from the core
    -- domain, both components carry them to the time base domain
    -- themselves.
    inc_driver: nsl_time.discipline.discipline_clock_driver
      generic map(
        clock_hz_c => clock_line_hz_c
        )
      port map(
        reset_n_i => core_reset_n_s,

        clock_i => clock_core_s,
        freq_offset_ppb_i => freq_ppb_s,

        rtc_clock_i => clock_line_s,
        sub_nanosecond_inc_o => inc_s
        );

    stepper: nsl_time.discipline.discipline_step_applier
      port map(
        reset_n_i => core_reset_n_s,

        clock_i => clock_core_s,
        reference_i => step_s,
        sync_i => step_sync_s,
        valid_i => step_valid_s,

        rtc_clock_i => clock_line_s,
        timestamp_i => time_s,
        timestamp_o => step_time_s,
        timestamp_set_o => step_time_set_s
        );

    time_base: nsl_time.clock.clock_adjustable
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        sub_nanosecond_inc_i => inc_s,

        timestamp_i => step_time_s,
        timestamp_set_i => step_time_set_s,

        timestamp_o => time_s
        );

    pps_ticker: nsl_time.pps.pps_ticker
      generic map(
        lead_ns_c => pps_output_lead_ns_c
        )
      port map(
        clock_i => clock_line_s,
        reset_n_i => line_reset_n_s,

        reference_i => time_s,

        tick_o => pps_tick_s
        );

    locked_sync: nsl_clocking.async.async_sampler
      generic map(
        cycle_count_c => 2,
        data_width_c => 1
        )
      port map(
        clock_i => clock_line_s,
        data_i(0) => locked_s,
        data_o(0) => locked_line_s
        );

    line_regs: process(clock_line_s, line_reset_n_s)
    begin
      if rising_edge(clock_line_s) then
        l <= lin;
      end if;
      if line_reset_n_s = '0' then
        l.second <= (others => '0');
        l.pps <= '0';
        l.pps_stretch <= 0;
      end if;
    end process;

    line_transition: process(l, time_s, pps_tick_s, locked_line_s)
    begin
      lin <= l;

      lin.second <= time_s.second;

      if pps_tick_s = '1' and locked_line_s = '1' then
        lin.pps <= '1';
        lin.pps_stretch <= pps_stretch_c;
      elsif l.pps_stretch /= 0 then
        lin.pps_stretch <= l.pps_stretch - 1;
      else
        lin.pps <= '0';
      end if;
    end process;

    -- The rising edge is the second boundary, the stretch only makes
    -- the pulse visible.
    pps_o <= l.pps;

    ----------------------------------------------------------------
    -- Line to core

    rx_cdc: nsl_amba.stream_fifo.axi4_stream_fifo
      generic map(
        config_c => axi4_flit_cfg,
        depth_c => 512,
        clock_count_c => 2
        )
      port map(
        clock_i(0) => clock_line_s,
        clock_i(1) => clock_core_s,
        reset_n_i => core_reset_n_s,

        in_i => rx_tagged_s.m,
        in_o => rx_tagged_s.s,
        in_free_o => open,

        out_o => rx_core_s.m,
        out_i => rx_core_s.s,
        out_available_o => open
        );

    tx_cdc: nsl_amba.stream_fifo.axi4_stream_fifo
      generic map(
        config_c => axi4_flit_cfg,
        depth_c => 512,
        clock_count_c => 2
        )
      port map(
        clock_i(0) => clock_core_s,
        clock_i(1) => clock_line_s,
        reset_n_i => core_reset_n_s,

        in_i => tx_s.m,
        in_o => tx_s.s,
        in_free_o => open,

        out_o => tx_line_s.m,
        out_i => tx_line_s.s,
        out_available_o => open
        );

    -- The second changes once a second: a settled copy is coherent.
    second_cross: nsl_clocking.interdomain.interdomain_reg
      generic map(
        data_width_c => 32,
        stable_count_c => 2
        )
      port map(
        clock_i => clock_core_s,
        data_i => std_ulogic_vector(l.second),
        data_o => second_core_s
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

    ----------------------------------------------------------------
    -- Core domain

    -- Errored frames are flagged with the user bit; drop them before
    -- they reach the stack.  Their capture register is simply never
    -- claimed.
    rx_error_s <= user(axi4_flit_cfg, rx_core_s.m)(0);

    rx_cleaner: nsl_amba.stream_fifo.axi4_stream_fifo_clean
      generic map(
        config_c => axi4_flit_cfg,
        fifo_word_count_l2 => 11
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        in_error_i => rx_error_s,
        in_i => rx_core_s.m,
        in_o => rx_core_s.s,

        out_o => rx_clean_s.m,
        out_i => rx_clean_s.s
        );

    mac_rx: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        in_i => rx_clean_s.m,
        in_o => rx_clean_s.s,
        out_o => mac_to_eth_s.m,
        out_i => mac_to_eth_s.s
        );

    eth: block is
      signal eth_to_mactx_s: bus_t;
    begin
      layer: nsl_inet.stream_ethernet.stream_ethernet_layer
        generic map(
          config_c => cfg_c,
          header_length_c => hdr_c,
          ethertype_c => (0 => ptp_ethertype_c),
          multicast_c => groups_c
          )
        port map(
          clock_i => clock_core_s,
          reset_n_i => core_reset_n_s,

          local_address_i => local_mac_c,

          to_l3_o(0) => eth_to_ptp_s.m,
          to_l3_i(0) => eth_to_ptp_s.s,
          from_l3_i(0) => ptp_to_eth_s.m,
          from_l3_o(0) => ptp_to_eth_s.s,

          to_l1_o => eth_to_mactx_s.m,
          to_l1_i => eth_to_mactx_s.s,
          from_l1_i => mac_to_eth_s.m,
          from_l1_o => mac_to_eth_s.s
          );

      mac_tx: nsl_inet.stream_mac.stream_mac_transmitter
        generic map(
          config_c => cfg_c,
          header_length_c => hdr_c
          )
        port map(
          clock_i => clock_core_s,
          reset_n_i => core_reset_n_s,

          in_i => eth_to_mactx_s.m,
          in_o => eth_to_mactx_s.s,
          out_o => tx_s.m,
          out_i => tx_s.s
          );
    end block;

    ptp: nsl_ptp.stream_l2.ptp_l2_slave
      generic map(
        config_c => cfg_c,
        header_length_c => blocks_c,
        clock_i_hz_c => clock_core_hz_c,
        domain_c => domain_c
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        clock_identity_i => identity_c,

        capture_id_o => capture_id_s,
        capture_time_i => rx_capture_time_s,

        tx_strobe_i => tx_done_s,
        tx_capture_time_i => tx_capture_time_s,

        rx_i => eth_to_ptp_s.m,
        rx_o => eth_to_ptp_s.s,
        tx_o => ptp_to_eth_s.m,
        tx_i => ptp_to_eth_s.s,

        offset_o => offset_s,
        offset_valid_o => offset_valid_s,
        step_o => step_s,
        step_sync_o => step_sync_s,
        step_valid_o => step_valid_s,
        path_delay_o => path_delay_s,
        locked_o => locked_s
        );

    servo: nsl_time.discipline.discipline_pi_servo
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        offset_i => r.offset,
        offset_valid_i => r.offset_valid,

        freq_offset_ppb_o => freq_ppb_s
        );

    regs: process(clock_core_s, core_reset_n_s)
    begin
      if rising_edge(clock_core_s) then
        r <= rin;
      end if;
      if core_reset_n_s = '0' then
        r.offset <= (others => '0');
        r.offset_valid <= '0';
        r.syncs <= (others => '0');
        r.steps <= (others => '0');
        r.rx_frames <= (others => '0');
        r.tx_frames <= (others => '0');
        r.tx_stamps <= (others => '0');
      end if;
    end process;

    transition: process(r, offset_s, offset_valid_s, step_valid_s,
                        tx_done_s, rx_core_s, tx_s)
    begin
      rin <= r;

      rin.offset_valid <= offset_valid_s;
      if offset_valid_s = '1' then
        rin.offset <= offset_s - to_signed(offset_correction_c, offset_s'length);
        rin.syncs <= r.syncs + 1;
      end if;

      if step_valid_s = '1' then
        rin.steps <= r.steps + 1;
      end if;

      if tx_done_s = '1' then
        rin.tx_stamps <= r.tx_stamps + 1;
      end if;

      if is_valid(cfg_c, rx_core_s.m) and is_ready(cfg_c, rx_core_s.s)
        and is_last(cfg_c, rx_core_s.m) then
        rin.rx_frames <= r.rx_frames + 1;
      end if;

      if is_valid(cfg_c, tx_s.m) and is_ready(cfg_c, tx_s.s)
        and is_last(cfg_c, tx_s.m) then
        rin.tx_frames <= r.tx_frames + 1;
      end if;
    end process;

    status_s.link_up <= link_up_core_s;
    status_s.locked <= locked_s;
    status_s.second <= unsigned(second_core_s);
    status_s.offset <= r.offset;
    status_s.path_delay <= path_delay_s;
    status_s.freq_ppb <= freq_ppb_s;
    status_s.syncs <= r.syncs;
    status_s.steps <= r.steps;
    status_s.rx_frames <= r.rx_frames;
    status_s.tx_frames <= r.tx_frames;
    status_s.tx_stamps <= r.tx_stamps;

    done_led_o <= link_up_s;
    ready_led_o <= locked_s;
  end block;

  ------------------------------------------------------------------
  -- Status screen on J7, in the core domain: status text laid out by
  -- the terminal, colors expanded from a palette, and the LCD driver.
  status_display: block is
    constant color_palette_c : rgb24_vector(0 to 7) := (
      rgb24_black,
      rgb24_red,
      rgb24_lime,
      rgb24_blue,
      rgb24_yellow,
      rgb24_cyan,
      rgb24_magenta,
      rgb24_white);

    constant geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(160, 80);
    constant pixel_config_c : nsl_video.pixel_stream.config_t
      := nsl_video.pixel_stream.config(pixels => 1);
    constant index_config_c : nsl_video.pixel_stream.config_t
      := nsl_video.pixel_stream.config(pixels => 1,
                                       component_bits => nsl_math.arith.log2(color_palette_c'length),
                                       colorspace => nsl_video.pixel_stream.COLORSPACE_INDEXED);
    constant pixel_palette_c : nsl_video.pixel_stream.pixel_vector(0 to color_palette_c'length-1)
      := nsl_video.pixel_stream.palette(pixel_config_c, color_palette_c);

    signal pixel_s, index_s: nsl_video.pixel_stream.bus_t;
    signal text_s: string(1 to screen_text_length_c);
    signal colors_s: label_color_vector(0 to screen_color_count_c-1);
  begin

    status: work.screen.screen_text
      generic map(
        utc_offset_c => utc_offset_c,
        display_utc_c => display_utc_c,
        asymmetry_ns_c => asymmetry_ns_c
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        link_up_i => status_s.link_up,
        locked_i => status_s.locked,
        second_i => status_s.second,
        offset_i => status_s.offset,
        path_delay_i => status_s.path_delay,
        freq_ppb_i => status_s.freq_ppb,
        sync_count_i => status_s.syncs,
        step_count_i => status_s.steps,
        rx_frames_i => status_s.rx_frames,
        tx_frames_i => status_s.tx_frames,

        text_o => text_s,
        colors_o => colors_s
        );

    terminal: nsl_video.terminal.terminal_labels_colormap
      generic map(
        row_count_l2_c => 4,
        column_count_l2_c => 5,
        character_count_l2_c => 8,
        color_count_l2_c => index_config_c.component_bits,
        font_c => nsl_indication.font_6x8.font_6x8_c,
        labels_c => screen_labels_c,
        blank_color_c => screen_color_background_c,
        config_c => index_config_c,
        geometry_c => geometry_c
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        enable_i => '1',
        out_o => index_s.m,
        out_i => index_s.s,

        text_i => text_s,
        color_i => colors_s
        );

    terminal_palette: nsl_video.colormap.palette_expander
      generic map(
        in_config_c => index_config_c,
        out_config_c => pixel_config_c
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        palette_i => pixel_palette_c,

        in_i => index_s.m,
        in_o => index_s.s,

        out_o => pixel_s.m,
        out_i => pixel_s.s
        );

    display: nsl_icesugar.pmod_lcd_096.pmod_lcd_096_driver
      generic map(
        clock_i_hz_c => clock_core_hz_c,
        config_c => pixel_config_c
        )
      port map(
        clock_i => clock_core_s,
        reset_n_i => core_reset_n_s,

        pixel_i => pixel_s.m,
        pixel_o => pixel_s.s,
        synced_o => open,

        pmod_io => j7_io
        );
  end block;

  ------------------------------------------------------------------
  -- Instrumentation: a gatecap rack on the Full Speed USB port,
  -- sampling the line in the line domain and showing the status as a
  -- panel in the core domain.
  instrumentation: block is
    signal usb_o_s: nsl_usb.io.usb_io_c;
    signal usb_i_s: nsl_usb.io.usb_io_s;
    signal panel_offset_s, panel_path_delay_s: unsigned(31 downto 0);
    signal panel_freq_ppb_s: unsigned(status_s.freq_ppb'length-1 downto 0);
  begin

    panel_offset_s <= unsigned(resize(status_s.offset, 32));
    panel_path_delay_s <= unsigned(resize(status_s.path_delay, 32));
    panel_freq_ppb_s <= unsigned(status_s.freq_ppb);

    observer: gatecap_generated.observer.observer_core
      generic map(
        burst_length_l2_c => 6
        )
      port map(
        clock_i => clock_usb_s,
        reset_n_i => usb_reset_n_s,

        usb_o => usb_o_s,
        usb_i => usb_i_s,
        online_o => open,

        line_sample_clock_i => clock_line_s,
        line_sample_reset_n_i => line_reset_n_s,
        line_sample_rx_i => probe_s.rx,
        line_sample_crs_i => crs_s,
        line_sample_tx_en_i => probe_s.tx_en,
        line_sample_tx_p_i => probe_s.tx_p,
        line_sample_link_up_i => link_up_s,

        panel_clock_i => clock_core_s,
        panel_reset_n_i => core_reset_n_s,
        panel_link_up_i => status_s.link_up,
        panel_locked_i => status_s.locked,
        panel_second_i => status_s.second,
        panel_offset_i => panel_offset_s,
        panel_path_delay_i => panel_path_delay_s,
        panel_freq_ppb_i => panel_freq_ppb_s,
        panel_syncs_i => status_s.syncs,
        panel_steps_i => status_s.steps,
        panel_rx_frames_i => status_s.rx_frames,
        panel_tx_frames_i => status_s.tx_frames,
        panel_tx_stamps_i => status_s.tx_stamps
        );

    usb_unused_io <= (others => 'Z');

    usb_pads: nsl_usb.io.io_fs_driver
      port map(
        bus_o => usb_i_s,
        bus_i => usb_o_s,
        bus_io.dp => usb_dp_io,
        bus_io.dm => usb_dn_io,
        dp_pullup_control_io => usb_dp_pullup_io
        );
  end block;

end arch;
