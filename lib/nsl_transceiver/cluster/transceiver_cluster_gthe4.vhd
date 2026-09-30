library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_data, nsl_math, nsl_hwdep, nsl_logic, nsl_clocking, nsl_synthesis;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.target.all;
use nsl_transceiver.lane.all;
use nsl_transceiver.transceiver_config_gtpe2.all;

library unisim;
use unisim.vcomponents.all;

entity transceiver_cluster is
  generic(
    config_c    : nsl_transceiver.cluster.config_t;
    ref_clock_c : integer_vector
    );
  port(
    reset_n_i : in std_ulogic;

    ref_clock_i : in std_ulogic_vector(0 to ref_clock_c'length-1);

    lane_tx_o : out nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);
    lane_rx_i : in  nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);

    lane_tx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);
    lane_rx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);

    tx_m_i : in  nsl_transceiver.lane.tx_master_vector(0 to config_c.lane_count-1);
    tx_s_o : out nsl_transceiver.lane.tx_slave_vector(0 to config_c.lane_count-1);
    rx_m_o : out nsl_transceiver.lane.rx_master_vector(0 to config_c.lane_count-1);
    rx_s_i : in  nsl_transceiver.lane.rx_slave_vector(0 to config_c.lane_count-1);

    -- This port is unused for the GTHE4 architecture. Resetting the PMA for a
    -- GTHE4 channel is equivalent to a full channel reset, use reset_n_i
    -- instead
    pma_reset_n_i : in std_ulogic_vector(0 to config_c.lane_count-1);

    -- APB clock for the user-facing master. Sourced internally from
    -- GTR12_QUADB's FABRIC_CM_LIFE_CLK_O loopback (the same clock
    -- the wizard uses for AHB / UPAR). The APB master and any
    -- companion logic on the configuration bus must clock on this
    -- output.
    apb_clock_o   : out std_ulogic;
    apb_reset_n_i : in  std_ulogic;
    apb_m_i       : in  nsl_amba.apb.master_t;
    apb_s_o       : out nsl_amba.apb.slave_t
    );
end entity;

architecture gthe4 of transceiver_cluster is

  -- Signal declarations --------------------------------------------------------------

  -- Clock signals
  signal s_refclk_vec : std_ulogic_vector(0 to 6);  -- 7 total clock signals
                                                    -- to assign
  signal s_stableclk  : std_ulogic;

  constant pll0_mult_div_config_c : pll_mult_div_t := pll_mult_div_assign(config_c.lanes(0).line_rate_mbps, config_c.plls(0).target_vco_mhz, config_c.plls(0).ref_clock_mhz);
  constant stable_clk_ref_mhz_c   : natural        := config_c.refclks(0).ref_clock_mhz;

  -- Error message constants
  constant lane_count_msg_c      : string := "transceiver_cluster/gthe4: GTHE4_CHANNEL primitive can have up to 4 lanes";
  constant pll_count_msg_c       : string := "transceiver_cluster/gthe4: GTHE4_COMMON exposes at most 2 quad-shared PLLs (PLL0/PLL1)";
  constant ref_clk_count_msg_c   : string := "transceiver_cluster/gthe4: GTHE4_CHANNEL exposes at most 7 reference clock inputs (gtrefclk0, gtwestrefclk0, etc.)";
  constant cluster_valid_msg_c   : string := "transceiver_cluster/gthe4: configuration failed target-agnostic consistency check";
  constant encoding_valid_msg_c  : string := "transceiver_cluster/gthe4: lane encoding not supported by this backend yet";
  constant data_byte_count_msg_c : string := "transceiver_cluster/gthe4: lane data_byte_count must be between >= 1 and <= 4";

begin

  assert config_c.lane_count <= 4
    report lane_count_msg_c
    severity failure;
  
  lane_count_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => lane_count_msg_c,
      condition_c => config_c.lane_count <= 4
      )
    port map(
      unused_i => '0'
      );  

  assert config_c.pll_count <= 2
    report pll_count_msg_c
    severity failure;

  pll_count_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => pll_count_msg_c,
      condition_c => config_c.pll_count <= 2
      )
    port map(
      unused_i => '0'
      );

  assert ref_clock_c'length <= 7
    report ref_clk_count_msg_c
    severity failure;

  ref_clk_count_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => ref_clk_count_msg_c,
      condition_c => ref_clock_c'length <= 7
      )
    port map(
      unused_i => '0'
      );  

  assert nsl_transceiver.cluster.is_valid(config_c)
    report cluster_valid_msg_c
    severity failure;

  cluster_valid_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => cluster_valid_msg_c,
      condition_c => nsl_transceiver.cluster.is_valid(config_c)
      )
    port map(
      unused_i => '0'
      );    

  encoding_check : for lane_idx in 0 to config_c.lane_count-1 generate
    encoding_supported : if config_c.lanes(lane_idx).enabled generate

      constant encoding_condition_c : boolean := config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_RAW
                                                 or config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_8B10B;
      constant data_byte_count_condition_c : boolean := config_c.lanes(lane_idx).data_byte_count >= 1
                                                        or config_c.lanes(lane_idx).data_byte_count <= 4;

      begin
      
        assert encoding_condition_c
          report encoding_valid_msg_c
          severity failure;

        cluster_valid_check : nsl_synthesis.assertion.synth_assert
          generic map(
            message_c   => encoding_valid_msg_c,
            condition_c => encoding_condition_c
            )
          port map(
            unused_i => '0'
            );          

        assert data_byte_count_condition_c
          report data_byte_count_msg_c
          severity failure;

        data_byte_check : nsl_synthesis.assertion.synth_assert
          generic map(
            message_c   => data_byte_count_msg_c,
            condition_c => data_byte_count_condition_c
            )
          port map(
            unused_i => '0'
            );

    end generate;
  end generate;

  -- Reference clock source routing. Each ref_clock_i entry is
  -- driven onto the primitive input matching the target-defined
  -- identifier in ref_clock_c(i).
  s_refclk_vec <= build_refclk_vec(ref_clock_c, ref_clock_i);
  s_stableclk  <= s_refclk_vec(clock_id("stableclk"));

  -- Lanes --------------------------------------------------------------------------------
  instantiate_lanes : for lane_idx in 0 to config_c.lane_count-1 generate

    signal s_gth_tx_rst            : std_logic;
    signal s_gth_rx_rst            : std_logic;
    signal s_drp_data_in        : std_logic_vector(15 downto 0);
    signal s_drp_data_out       : std_logic_vector(15 downto 0);
    signal s_drp_addr           : std_logic_vector(9 downto 0);
    signal s_drp_en             : std_logic;
    signal s_drp_wr             : std_logic;
    signal s_drp_rdy            : std_logic;
    signal s_gt_power_good      : std_logic;
    signal s_gt_power_good_sync : std_logic;
    signal s_rx_pma_rst_done       : std_logic;
    signal s_tx_pma_rst_done       : std_logic;
    signal s_pll_locked_sync    : std_logic;
    signal s_rx_pma_rst_done_sync  : std_logic;
    signal s_tx_pma_rst_done_sync  : std_logic;

    signal s_txoutclk_buff         : std_ulogic;
    signal s_parallel_clock        : std_ulogic;
    signal s_parallel_clock_buff   : std_ulogic;
    signal s_parallel_reset_sync_n : std_ulogic;
    signal s_txusrclk2             : std_ulogic;
    signal s_txusrclk2_buff        : std_ulogic;

    signal s_pll_locked : std_logic;

    signal s_pll_pd         : std_logic;
    signal s_pll_reset_done : std_logic;

    -- 2us + a little more to play it safe
    constant delay2us_c : natural := stable_clk_ref_mhz_c * 2 + stable_clk_ref_mhz_c / 10;

    type reset_state_pll_t is (
      ST_RESET,
      ST_HOLD_RST,
      ST_WAIT_PWR_GOOD,
      ST_DONE);

    type regs_pll_t is
    record
      state     : reset_state_pll_t;
      pll_count : natural;
      pll_pd    : std_logic;
      pll_done  : std_ulogic;
    end record;

    signal r_pll, rin_pll : regs_pll_t;

    signal s_rx_ready     : std_logic;
    signal s_tx_ready     : std_logic;
    signal s_gth_rx_data  : std_logic_vector(127 downto 0) := (others => '0');
    signal s_gth_tx_data  : std_logic_vector(127 downto 0) := (others => '0');
    signal s_tx_out_clock : std_logic;
    signal s_rxctrl0      : std_logic_vector(15 downto 0);
    signal s_rxctrl1      : std_logic_vector(15 downto 0);
    signal s_rxctrl3      : std_logic_vector(7 downto 0);
    signal s_rxcharisk    : std_logic_vector(3 downto 0);
    signal s_rxdisperr    : std_logic_vector(3 downto 0);
    signal s_rxcodeerr    : std_logic_vector(3 downto 0);
    signal s_txcharisk    : std_logic_vector(3 downto 0);
    signal s_txctrl2      : std_logic_vector(7 downto 0);

    signal s_pcomma_align_en : std_logic;
    signal s_mcomma_align_en : std_logic;
    signal s_cdr_hold        : std_logic;

    signal s_align_ready : std_ulogic_vector(0 downto 0);
    
    type reset_state_t is (
      ST_RESET,
      ST_WAIT_PLL,
      ST_WAIT_PMA_LOW,
      ST_WAIT_PWR_GOOD,
      ST_WAIT_PMA_HIGH,
      ST_DONE);

    type regs_t is
    record
      state   : reset_state_t;
      gth_rst : std_ulogic;
      timeout : natural;
    end record;

    signal r_rx, rin_rx, r_tx, rin_tx : regs_t;

    constant loopback_config_c     : loopback_config_t := loopback_configure(config_c.lanes(lane_idx).loopback);
    constant pll_mult_div_config_c : pll_mult_div_t    := pll0_mult_div_config_c;

    constant data_byte_count_c   : natural      := config_c.lanes(lane_idx).data_byte_count;
    constant data_width_config_c : data_width_t := determine_data_width(data_byte_count_c);
    constant data_bit_count_c    : natural      := config_c.lanes(lane_idx).data_byte_count * 8;
    constant data_width_ratio_c  : natural      := data_width_config_c.interface_width / data_bit_count_c;
    constant timeout_delay_c     : natural      := stable_clk_ref_mhz_c * 1_000_000;

    signal s_rx_data_to_adapter   : std_ulogic_vector(data_bit_count_c - 1 downto 0) := (others => '0');
    signal s_tx_data_from_adapter : std_ulogic_vector(data_bit_count_c - 1 downto 0) := (others => '0');

  begin

    -- TX and RX Data ------------------------------------------------------------
    packunpack : for i in 0 to data_byte_count_c - 1 generate
      s_tx_data_from_adapter(8*i + 7 downto 8*i) <= tx_m_i(lane_idx).data(i);
      rx_m_o(lane_idx).data(i)                   <= s_rx_data_to_adapter(8*i + 7 downto 8*i);
    end generate;

    -- CPLL reset ----------------------------------------------------------------
    s_pll_pd         <= r_pll.pll_pd;
    s_pll_reset_done <= r_pll.pll_done;

    gth_power_good_sync : nsl_clocking.async.async_deglitcher
      port map(
        clock_i => s_stableclk,
        data_i  => s_gt_power_good,
        data_o  => s_gt_power_good_sync
        );    

    -- PLL Reset
    reg_pll : process(reset_n_i, s_stableclk)
    begin
      if rising_edge(s_stableclk) then
        r_pll <= rin_pll;
      end if;

      if reset_n_i = '0' then
        r_pll.state <= ST_RESET;
      end if;
    end process;

    transition_pll : process(r_pll, s_gt_power_good_sync) is

    begin
      rin_pll <= r_pll;

      case r_pll.state is
        when ST_RESET =>
          rin_pll.pll_count <= 0;
          rin_pll.pll_pd    <= '0';
          rin_pll.pll_done  <= '0';
          rin_pll.state     <= ST_HOLD_RST;
        when ST_HOLD_RST =>
          rin_pll.pll_count <= r_pll.pll_count + 1;
          rin_pll.pll_pd    <= '1';
          if r_pll.pll_count = delay2us_c then
            rin_pll.state <= ST_WAIT_PWR_GOOD;
          end if;
        when ST_WAIT_PWR_GOOD =>
          if s_gt_power_good_sync = '1' then
            rin_pll.state <= ST_DONE;
          end if;
        when ST_DONE =>
          rin_pll.pll_pd   <= '0';
          rin_pll.pll_done <= '1';
      end case;

    end process;

    -- GTH reset -----------------------------------------------------------------
    s_gth_rx_rst  <= r_rx.gth_rst;
    s_gth_tx_rst  <= r_tx.gth_rst;
    s_rx_ready <= s_rx_pma_rst_done_sync;
    s_tx_ready <= s_tx_pma_rst_done_sync;

    -- De-glitch asynchronous signals
    pll_locked_sync : nsl_clocking.async.async_deglitcher
      port map(
        clock_i => s_stableclk,
        data_i  => s_pll_locked,
        data_o  => s_pll_locked_sync
        );

    rx_pma_rst_done_sync : nsl_clocking.async.async_deglitcher
      port map(
        clock_i => s_stableclk,
        data_i  => s_rx_pma_rst_done,
        data_o  => s_rx_pma_rst_done_sync
        );

    tx_pma_rst_done_sync : nsl_clocking.async.async_deglitcher
      port map(
        clock_i => s_stableclk,
        data_i  => s_tx_pma_rst_done,
        data_o  => s_tx_pma_rst_done_sync
        );                

    -- Reset FSM
    reg_rx : process(reset_n_i, s_stableclk)
    begin
      if rising_edge(s_stableclk) then
        r_rx <= rin_rx;
        if r_rx.timeout = 0 then
          r_rx.state <= ST_RESET;
        end if;
      end if;

      if reset_n_i = '0' then
        r_rx.state <= ST_RESET;
      end if;
    end process;

    transition_rx : process(r_rx, s_gt_power_good_sync, s_pll_locked_sync,
                            s_pll_reset_done, s_rx_pma_rst_done_sync) is

    begin
      rin_rx         <= r_rx;
      rin_rx.timeout <= r_rx.timeout - 1;

      case r_rx.state is
        when ST_RESET =>
          rin_rx.state   <= ST_WAIT_PLL;
          rin_rx.gth_rst <= '1';
          rin_rx.timeout <= timeout_delay_c;
        when ST_WAIT_PLL =>
          rin_rx.gth_rst <= '1';
          if s_pll_locked_sync = '1' and s_pll_reset_done = '1' then
            rin_rx.state <= ST_WAIT_PMA_LOW;
          end if;
        when ST_WAIT_PMA_LOW =>
          if s_rx_pma_rst_done_sync = '0' then
            rin_rx.state <= ST_WAIT_PWR_GOOD;
          end if;
        when ST_WAIT_PWR_GOOD =>
          if s_gt_power_good_sync = '1' then
            rin_rx.state <= ST_WAIT_PMA_HIGH;
          end if;          
        when ST_WAIT_PMA_HIGH =>
          rin_rx.gth_rst <= '0';
          if s_rx_pma_rst_done_sync = '1' then
            rin_rx.state <= ST_DONE;
          end if;
        when ST_DONE =>
          rin_rx.timeout <= timeout_delay_c;
      end case;

    end process;

    reg_tx : process(reset_n_i, s_stableclk)
    begin
      if rising_edge(s_stableclk) then
        r_tx <= rin_tx;
        if r_tx.timeout = 0 then
          r_tx.state <= ST_RESET;
        end if;
      end if;

      if reset_n_i = '0' then
        r_tx.state <= ST_RESET;
      end if;
    end process;

    transition_tx : process(r_tx, s_gt_power_good_sync, s_pll_locked_sync,
                            s_pll_reset_done, s_tx_pma_rst_done_sync) is

    begin
      rin_tx         <= r_tx;
      rin_tx.timeout <= r_tx.timeout - 1;

      case r_tx.state is
        when ST_RESET =>
          rin_tx.state   <= ST_WAIT_PLL;
          rin_tx.gth_rst <= '1';
          rin_tx.timeout <= timeout_delay_c;
        when ST_WAIT_PLL =>
          rin_tx.gth_rst <= '1';
          if s_pll_locked_sync = '1' and s_pll_reset_done = '1' then
            rin_tx.state <= ST_WAIT_PMA_LOW;
          end if;
        when ST_WAIT_PMA_LOW =>
          if s_tx_pma_rst_done_sync = '0' then
            rin_tx.state <= ST_WAIT_PWR_GOOD;
          end if;
        when ST_WAIT_PWR_GOOD =>
          if s_gt_power_good_sync = '1' then
            rin_tx.state <= ST_WAIT_PMA_HIGH;
          end if;          
        when ST_WAIT_PMA_HIGH =>
          rin_tx.gth_rst <= '0';
          if s_tx_pma_rst_done_sync = '1' then
            rin_tx.state <= ST_DONE;
          end if;
        when ST_DONE =>
          rin_tx.timeout <= timeout_delay_c;
      end case;

    end process;    

    -- Gearbox -----------------------------------------------------------------

    gearbox : block is

      -- Use data_width_config_c and data_width_ratio_c to determine widths
      signal s_rx_charisk_gear  : std_ulogic_vector(data_byte_count_c - 1 downto 0);
      signal s_tx_charisk_gear  : std_ulogic_vector(data_byte_count_c - 1 downto 0);
      signal s_rx_disperr_gear  : std_ulogic_vector(data_byte_count_c - 1 downto 0);
      signal s_rx_codeerr_gear  : std_ulogic_vector(data_byte_count_c - 1 downto 0);
      signal s_txcharisk_vec    : std_ulogic_vector(3 downto 0);
      signal s_gth_tx_data_stdu : std_ulogic_vector(data_width_config_c.interface_width - 1 downto 0);

    begin

      rx_m_o(lane_idx).status(data_byte_count_c * 1 - 1 downto data_byte_count_c * 0) <= s_rx_charisk_gear;
      rx_m_o(lane_idx).status(data_byte_count_c * 2 - 1 downto data_byte_count_c * 1) <= s_rx_disperr_gear;
      rx_m_o(lane_idx).status(data_byte_count_c * 3 - 1 downto data_byte_count_c * 2) <= s_rx_codeerr_gear;
      s_tx_charisk_gear                                                               <= tx_m_i(lane_idx).control(data_byte_count_c - 1 downto 0);
      s_txcharisk                                                                     <= std_logic_vector(s_txcharisk_vec);
      s_gth_tx_data(data_width_config_c.interface_width - 1 downto 0)                 <= std_logic_vector(s_gth_tx_data_stdu);
      s_rxcharisk(3 downto 0)                                                         <= s_rxctrl0(3 downto 0);
      s_rxdisperr(3 downto 0)                                                         <= s_rxctrl1(3 downto 0);
      s_rxcodeerr(3 downto 0)                                                         <= s_rxctrl3(3 downto 0);
      s_txctrl2                                                                       <= (3 => s_txcharisk(3), 2 => s_txcharisk(2), 1 => s_txcharisk(1), 0 => s_txcharisk(0), others => '0');

      gearbox_datafromrx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_width_config_c.interface_width,
          output_width_c  => data_bit_count_c,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => std_ulogic_vector(s_gth_rx_data(data_width_config_c.interface_width - 1 downto 0)),
          out_o     => s_rx_data_to_adapter
          );

      gearbox_controlfromrx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_byte_count_c * 2,
          output_width_c  => data_byte_count_c,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => std_ulogic_vector(s_rxcharisk((data_byte_count_c * 2 - 1) downto 0)),
          out_o     => s_rx_charisk_gear
          );

      gearbox_disperrfromrx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_byte_count_c * 2,
          output_width_c  => data_byte_count_c,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => std_ulogic_vector(s_rxdisperr((data_byte_count_c * 2 - 1) downto 0)),
          out_o     => s_rx_disperr_gear
          );

      gearbox_codeerrfromrx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_byte_count_c * 2,
          output_width_c  => data_byte_count_c,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => std_ulogic_vector(s_rxcodeerr((data_byte_count_c * 2 - 1) downto 0)),
          out_o     => s_rx_codeerr_gear
          );    

      gearbox_datatotx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_bit_count_c,
          output_width_c  => data_width_config_c.interface_width,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => s_tx_data_from_adapter,
          out_o     => s_gth_tx_data_stdu
          );

      gearbox_controltotx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_byte_count_c,
          output_width_c  => data_byte_count_c * 2,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => s_tx_charisk_gear,
          out_o     => s_txcharisk_vec((data_byte_count_c * 2) - 1 downto 0)
          );

    end block;

  -- Aligner --------------------------------------------------------------------------------

    need_alignment : if (config_c.lanes(lane_idx).loopback = nsl_transceiver.lane.LOOPBACK_NONE) or
                        (config_c.lanes(lane_idx).loopback = nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA) or
                        (config_c.lanes(lane_idx).loopback = nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS) or
                        (config_c.lanes(lane_idx).loopback = nsl_transceiver.lane.LOOPBACK_FAR_END_PCS) generate
      -- Alignment done
      s_pcomma_align_en                                                               <= not(s_align_ready(0));
      s_mcomma_align_en                                                               <= not(s_align_ready(0));
      s_cdr_hold                                                                      <= '0';
      rx_m_o(lane_idx).status(data_byte_count_c * 4 - 1 downto data_byte_count_c * 3) <= s_align_ready;

      aligner : nsl_io.delay.input_delay_aligner_slow
        generic map(
          stabilization_delay_c => 300,
          stabilization_cycle_c => 300
          )
        port map(
          clock_i   => s_parallel_clock_buff,
          reset_n_i => tx_m_i(lane_idx).control(data_byte_count_c * 2),

          delay_mark_i  => '1',
          serdes_mark_i => '1',

          restart_i => tx_m_i(lane_idx).control(data_byte_count_c * 3),
          valid_i   => tx_m_i(lane_idx).control(data_byte_count_c * 1),
          ready_o   => s_align_ready(0)
          );
    end generate;

    no_align : if (config_c.lanes(lane_idx).loopback = nsl_transceiver.lane.LOOPBACK_FAR_END_PMA) generate
      s_pcomma_align_en                                                               <= '0';
      s_mcomma_align_en                                                               <= '0';
      s_cdr_hold                                                                      <= '0';
      s_align_ready(0)                                                                <= '1';
      rx_m_o(lane_idx).status(data_byte_count_c * 4 - 1 downto data_byte_count_c * 3) <= s_align_ready;
    end generate;

    -- Clocking and MMCM if necessary ------------------------------------------------------------

    clocking : block

      signal s_domain_a_pll_reset      : std_ulogic;
      signal s_domain_a_pll_locked     : std_ulogic;
      signal s_domain_a_pll_locked_vec : std_ulogic_vector(0 downto 0);
      signal s_domain_a_pll_feedback   : std_ulogic;

    begin

      lane_tx_clock_o(lane_idx) <= s_parallel_clock_buff;
      -- FIXME: debug
      lane_rx_clock_o(lane_idx) <= s_txusrclk2_buff;

      mmcm_gen : if data_width_ratio_c /= 1 generate

        constant input_hz_c        : natural := config_c.lanes(lane_idx).line_rate_mbps * 50000;
        constant input_period_ns_c : real    := 1.0e9 / real(input_hz_c);
        constant output_hz_c       : natural := input_hz_c * data_width_ratio_c;

        constant p : params := pll_params_calc(input_hz_c, output_hz_c, S7_MMCM);

        begin

          s_domain_a_pll_locked <= s_pll_locked_sync;
          
          BUFG_GT_parallelclk : BUFG_GT
            generic map (
              SIM_DEVICE => "ULTRASCALE_PLUS"  -- ULTRASCALE, ULTRASCALE_PLUS
              )
            port map (
              O       => s_parallel_clock_buff,
              CE      => '1',
              CEMASK  => '0',
              CLR     => '0',
              CLRMASK => '0',
              DIV     => "000",
              I       => s_tx_out_clock
              );                          

          BUFG_GT_txusrclk : BUFG_GT
            generic map (
              SIM_DEVICE => "ULTRASCALE_PLUS"  -- ULTRASCALE, ULTRASCALE_PLUS
              )
            port map (
              O       => s_txusrclk2_buff,
              CE      => '1',
              CEMASK  => '0',
              CLR     => '0',
              CLRMASK => '0',
              DIV     => "001",
              I       => s_tx_out_clock
              );                          

      end generate;

        no_mmcm_gen : if data_width_ratio_c = 1 generate  -- Data width between adapter and transceiver is the same

          -- No MMCM needed
          s_parallel_clock_buff <= s_txoutclk_buff;
          s_txusrclk2_buff      <= s_txoutclk_buff;
          s_domain_a_pll_locked <= s_pll_locked_sync;
        
        end generate;

      s_domain_a_pll_locked_vec(0)                                                    <= s_domain_a_pll_locked;
      rx_m_o(lane_idx).status(data_byte_count_c * 5 - 1 downto data_byte_count_c * 4) <= s_domain_a_pll_locked_vec;

      general_reset_sync : nsl_clocking.async.async_edge
        port map(
          clock_i => s_parallel_clock_buff,
          data_i  => s_domain_a_pll_locked,
          data_o  => s_parallel_reset_sync_n
          );    

    end block;

    -- Lane instance ----------------------------------------------------------------
    gthe4_i : GTHE4_CHANNEL
      generic map
      (
        ACJTAG_DEBUG_MODE            => '0',
        ACJTAG_MODE                  => '0',
        ACJTAG_RESET                 => '0',
        ADAPT_CFG0                   => "0001000000000000",
        ADAPT_CFG1                   => "1100100000000000",
        ADAPT_CFG2                   => "0000000000000000",
        ALIGN_COMMA_DOUBLE           => "FALSE",
        ALIGN_COMMA_ENABLE           => "1111111111",
        ALIGN_COMMA_WORD             => 2,
        ALIGN_MCOMMA_DET             => "TRUE",
        ALIGN_MCOMMA_VALUE           => "1010000011",
        ALIGN_PCOMMA_DET             => "TRUE",
        ALIGN_PCOMMA_VALUE           => "0101111100",
        A_RXOSCALRESET               => '0',
        A_RXPROGDIVRESET             => '0',
        A_RXTERMINATION              => '1',
        A_TXDIFFCTRL                 => "01100",
        A_TXPROGDIVRESET             => '0',
        CAPBYPASS_FORCE              => '0',
        CBCC_DATA_SOURCE_SEL         => "DECODED",
        CDR_SWAP_MODE_EN             => '0',
        CFOK_PWRSVE_EN               => '1',
        CHAN_BOND_KEEP_ALIGN         => "FALSE",
        CHAN_BOND_MAX_SKEW           => 1,
        CHAN_BOND_SEQ_1_1            => "0000000000",
        CHAN_BOND_SEQ_1_2            => "0000000000",
        CHAN_BOND_SEQ_1_3            => "0000000000",
        CHAN_BOND_SEQ_1_4            => "0000000000",
        CHAN_BOND_SEQ_1_ENABLE       => "1111",
        CHAN_BOND_SEQ_2_1            => "0000000000",
        CHAN_BOND_SEQ_2_2            => "0000000000",
        CHAN_BOND_SEQ_2_3            => "0000000000",
        CHAN_BOND_SEQ_2_4            => "0000000000",
        CHAN_BOND_SEQ_2_ENABLE       => "1111",
        CHAN_BOND_SEQ_2_USE          => "FALSE",
        CHAN_BOND_SEQ_LEN            => 1,
        CH_HSPMUX                    => "0011110000111100",
        CKCAL1_CFG_0                 => "1100000011000000",
        CKCAL1_CFG_1                 => "0101000011000000",
        CKCAL1_CFG_2                 => "0000000000001010",
        CKCAL1_CFG_3                 => "0000000000000000",
        CKCAL2_CFG_0                 => "1100000011000000",
        CKCAL2_CFG_1                 => "1000000011000000",
        CKCAL2_CFG_2                 => "0000000000000000",
        CKCAL2_CFG_3                 => "0000000000000000",
        CKCAL2_CFG_4                 => "0000000000000000",
        CKCAL_RSVD0                  => "0000000010000000",
        CKCAL_RSVD1                  => "0000010000000000",
        CLK_CORRECT_USE              => "TRUE",
        CLK_COR_KEEP_IDLE            => "FALSE",
        CLK_COR_MAX_LAT              => 15,
        CLK_COR_MIN_LAT              => 12,
        CLK_COR_PRECEDENCE           => "TRUE",
        CLK_COR_REPEAT_WAIT          => 0,
        CLK_COR_SEQ_1_1              => "0110111100",  -- K28.5
        CLK_COR_SEQ_1_2              => "0001010000",  -- D16.2
        CLK_COR_SEQ_1_3              => "0000000000",
        CLK_COR_SEQ_1_4              => "0000000000",
        CLK_COR_SEQ_1_ENABLE         => "1111",
        CLK_COR_SEQ_2_1              => "0110111100",  -- K28.5
        CLK_COR_SEQ_2_2              => "0011000101",  -- D5.6
        CLK_COR_SEQ_2_3              => "0000000000",
        CLK_COR_SEQ_2_4              => "0000000000",
        CLK_COR_SEQ_2_ENABLE         => "1111",
        CLK_COR_SEQ_2_USE            => "TRUE",
        CLK_COR_SEQ_LEN              => 2,
        CPLL_CFG0                    => "0000000111111010",
        CPLL_CFG1                    => "0000000000100011",
        CPLL_CFG2                    => "0000000000000010",
        CPLL_CFG3                    => "0000000000000000",
        CPLL_FBDIV                   => pll_mult_div_config_c.N2,
        CPLL_FBDIV_45                => pll_mult_div_config_c.N1,
        CPLL_INIT_CFG0               => "0000001010110010",
        CPLL_LOCK_CFG                => "0000000111101000",
        CPLL_REFCLK_DIV              => pll_mult_div_config_c.M,
        CTLE3_OCAP_EXT_CTRL          => "000",
        CTLE3_OCAP_EXT_EN            => '0',
        DDI_CTRL                     => "00",
        DDI_REALIGN_WAIT             => 15,
        DEC_MCOMMA_DETECT            => "TRUE",
        DEC_PCOMMA_DETECT            => "TRUE",
        DEC_VALID_COMMA_ONLY         => "FALSE",
        DELAY_ELEC                   => '0',
        DMONITOR_CFG0                => "0000000000",
        DMONITOR_CFG1                => "00000000",
        ES_CLK_PHASE_SEL             => '0',
        ES_CONTROL                   => "000000",
        ES_ERRDET_EN                 => "FALSE",
        ES_EYE_SCAN_EN               => "FALSE",
        ES_HORZ_OFFSET               => "000000000000",
        ES_PRESCALE                  => "00000",
        ES_QUALIFIER0                => "0000000000000000",
        ES_QUALIFIER1                => "0000000000000000",
        ES_QUALIFIER2                => "0000000000000000",
        ES_QUALIFIER3                => "0000000000000000",
        ES_QUALIFIER4                => "0000000000000000",
        ES_QUALIFIER5                => "0000000000000000",
        ES_QUALIFIER6                => "0000000000000000",
        ES_QUALIFIER7                => "0000000000000000",
        ES_QUALIFIER8                => "0000000000000000",
        ES_QUALIFIER9                => "0000000000000000",
        ES_QUAL_MASK0                => "0000000000000000",
        ES_QUAL_MASK1                => "0000000000000000",
        ES_QUAL_MASK2                => "0000000000000000",
        ES_QUAL_MASK3                => "0000000000000000",
        ES_QUAL_MASK4                => "0000000000000000",
        ES_QUAL_MASK5                => "0000000000000000",
        ES_QUAL_MASK6                => "0000000000000000",
        ES_QUAL_MASK7                => "0000000000000000",
        ES_QUAL_MASK8                => "0000000000000000",
        ES_QUAL_MASK9                => "0000000000000000",
        ES_SDATA_MASK0               => "0000000000000000",
        ES_SDATA_MASK1               => "0000000000000000",
        ES_SDATA_MASK2               => "0000000000000000",
        ES_SDATA_MASK3               => "0000000000000000",
        ES_SDATA_MASK4               => "0000000000000000",
        ES_SDATA_MASK5               => "0000000000000000",
        ES_SDATA_MASK6               => "0000000000000000",
        ES_SDATA_MASK7               => "0000000000000000",
        ES_SDATA_MASK8               => "0000000000000000",
        ES_SDATA_MASK9               => "0000000000000000",
        EYE_SCAN_SWAP_EN             => '0',
        FTS_DESKEW_SEQ_ENABLE        => "1111",
        FTS_LANE_DESKEW_CFG          => "1111",
        FTS_LANE_DESKEW_EN           => "FALSE",
        GEARBOX_MODE                 => "00000",
        ISCAN_CK_PH_SEL2             => '0',
        LOCAL_MASTER                 => '1',
        LPBK_BIAS_CTRL               => "100",
        LPBK_EN_RCAL_B               => '0',
        LPBK_EXT_RCAL                => "1000",
        LPBK_IND_CTRL0               => "000",
        LPBK_IND_CTRL1               => "000",
        LPBK_IND_CTRL2               => "000",
        LPBK_RG_CTRL                 => "1110",
        OOBDIVCTL                    => "00",
        OOB_PWRUP                    => '0',
        PCI3_AUTO_REALIGN            => "OVR_1K_BLK",
        PCI3_PIPE_RX_ELECIDLE        => '0',
        PCI3_RX_ASYNC_EBUF_BYPASS    => "00",
        PCI3_RX_ELECIDLE_EI2_ENABLE  => '0',
        PCI3_RX_ELECIDLE_H2L_COUNT   => "000000",
        PCI3_RX_ELECIDLE_H2L_DISABLE => "000",
        PCI3_RX_ELECIDLE_HI_COUNT    => "000000",
        PCI3_RX_ELECIDLE_LP4_DISABLE => '0',
        PCI3_RX_FIFO_DISABLE         => '0',
        PCIE3_CLK_COR_EMPTY_THRSH    => "00000",
        PCIE3_CLK_COR_FULL_THRSH     => "010000",
        PCIE3_CLK_COR_MAX_LAT        => "00100",
        PCIE3_CLK_COR_MIN_LAT        => "00000",
        PCIE3_CLK_COR_THRSH_TIMER    => "001000",
        PCIE_BUFG_DIV_CTRL           => "0001000000000000",
        PCIE_PLL_SEL_MODE_GEN12      => "00",
        PCIE_PLL_SEL_MODE_GEN3       => "11",
        PCIE_PLL_SEL_MODE_GEN4       => "10",
        PCIE_RXPCS_CFG_GEN3          => "0000101010100101",
        PCIE_RXPMA_CFG               => "0010100000001010",
        PCIE_TXPCS_CFG_GEN3          => "0010110010100100",
        PCIE_TXPMA_CFG               => "0010100000001010",
        PCS_PCIE_EN                  => "FALSE",
        PCS_RSVD0                    => "0000000000000000",
        PD_TRANS_TIME_FROM_P2        => "000000111100",
        PD_TRANS_TIME_NONE_P2        => "00011001",
        PD_TRANS_TIME_TO_P2          => "01100100",
        PREIQ_FREQ_BST               => 0,
        PROCESS_PAR                  => "010",
        RATE_SW_USE_DRP              => '1',
        RCLK_SIPO_DLY_ENB            => '0',
        RCLK_SIPO_INV_EN             => '0',
        RESET_POWERSAVE_DISABLE      => '0',
        RTX_BUF_CML_CTRL             => "010",
        RTX_BUF_TERM_CTRL            => "00",
        RXBUFRESET_TIME              => "00011",
        RXBUF_ADDR_MODE              => "FULL",
        RXBUF_EIDLE_HI_CNT           => "1000",
        RXBUF_EIDLE_LO_CNT           => "0000",
        RXBUF_EN                     => "TRUE",
        RXBUF_RESET_ON_CB_CHANGE     => "TRUE",
        RXBUF_RESET_ON_COMMAALIGN    => "FALSE",
        RXBUF_RESET_ON_EIDLE         => "FALSE",
        RXBUF_RESET_ON_RATE_CHANGE   => "TRUE",
        RXBUF_THRESH_OVFLW           => 0,
        RXBUF_THRESH_OVRD            => "FALSE",
        RXBUF_THRESH_UNDFLW          => 4,
        RXCDRFREQRESET_TIME          => "00001",
        RXCDRPHRESET_TIME            => "00001",
        RXCDR_CFG0                   => "0000000000000011",
        RXCDR_CFG0_GEN3              => "0000000000000011",
        RXCDR_CFG1                   => "0000000000000000",
        RXCDR_CFG1_GEN3              => "0000000000000000",
        RXCDR_CFG2                   => "0000001001001001",
        RXCDR_CFG2_GEN2              => "1001001001",
        RXCDR_CFG2_GEN3              => "0000001001001001",
        RXCDR_CFG2_GEN4              => "0000000101100100",
        RXCDR_CFG3                   => "0000000000010010",
        RXCDR_CFG3_GEN2              => "010010",
        RXCDR_CFG3_GEN3              => "0000000000010010",
        RXCDR_CFG3_GEN4              => "0000000000010010",
        RXCDR_CFG4                   => "0101110011110110",
        RXCDR_CFG4_GEN3              => "0101110011110110",
        RXCDR_CFG5                   => "1011010001101011",
        RXCDR_CFG5_GEN3              => "0001010001101011",
        RXCDR_FR_RESET_ON_EIDLE      => '0',
        RXCDR_HOLD_DURING_EIDLE      => '0',
        RXCDR_LOCK_CFG0              => "0010001000000001",
        RXCDR_LOCK_CFG1              => "1001111111111111",
        RXCDR_LOCK_CFG2              => "0111011111000011",
        RXCDR_LOCK_CFG3              => "0000000000000001",
        RXCDR_LOCK_CFG4              => "0000000000000000",
        RXCDR_PH_RESET_ON_EIDLE      => '0',
        RXCFOK_CFG0                  => "0000000000000000",
        RXCFOK_CFG1                  => "1000000000010101",
        RXCFOK_CFG2                  => "0000001010101110",
        RXCKCAL1_IQ_LOOP_RST_CFG     => "0000000000000100",
        RXCKCAL1_I_LOOP_RST_CFG      => "0000000000000100",
        RXCKCAL1_Q_LOOP_RST_CFG      => "0000000000000100",
        RXCKCAL2_DX_LOOP_RST_CFG     => "0000000000000100",
        RXCKCAL2_D_LOOP_RST_CFG      => "0000000000000100",
        RXCKCAL2_S_LOOP_RST_CFG      => "0000000000000100",
        RXCKCAL2_X_LOOP_RST_CFG      => "0000000000000100",
        RXDFELPMRESET_TIME           => "0001111",
        RXDFELPM_KL_CFG0             => "0000000000000000",
        RXDFELPM_KL_CFG1             => "1010000011100010",
        RXDFELPM_KL_CFG2             => "0000000100000000",
        RXDFE_CFG0                   => "0000101000000000",
        RXDFE_CFG1                   => "0000000000000000",
        RXDFE_GC_CFG0                => "0000000000000000",
        RXDFE_GC_CFG1                => "1000000000000000",
        RXDFE_GC_CFG2                => "1111111111100000",
        RXDFE_H2_CFG0                => "0000000000000000",
        RXDFE_H2_CFG1                => "0000000000000010",
        RXDFE_H3_CFG0                => "0000000000000000",
        RXDFE_H3_CFG1                => "1000000000000010",
        RXDFE_H4_CFG0                => "0000000000000000",
        RXDFE_H4_CFG1                => "1000000000000010",
        RXDFE_H5_CFG0                => "0000000000000000",
        RXDFE_H5_CFG1                => "1000000000000010",
        RXDFE_H6_CFG0                => "0000000000000000",
        RXDFE_H6_CFG1                => "1000000000000010",
        RXDFE_H7_CFG0                => "0000000000000000",
        RXDFE_H7_CFG1                => "1000000000000010",
        RXDFE_H8_CFG0                => "0000000000000000",
        RXDFE_H8_CFG1                => "1000000000000010",
        RXDFE_H9_CFG0                => "0000000000000000",
        RXDFE_H9_CFG1                => "1000000000000010",
        RXDFE_HA_CFG0                => "0000000000000000",
        RXDFE_HA_CFG1                => "1000000000000010",
        RXDFE_HB_CFG0                => "0000000000000000",
        RXDFE_HB_CFG1                => "1000000000000010",
        RXDFE_HC_CFG0                => "0000000000000000",
        RXDFE_HC_CFG1                => "1000000000000010",
        RXDFE_HD_CFG0                => "0000000000000000",
        RXDFE_HD_CFG1                => "1000000000000010",
        RXDFE_HE_CFG0                => "0000000000000000",
        RXDFE_HE_CFG1                => "1000000000000010",
        RXDFE_HF_CFG0                => "0000000000000000",
        RXDFE_HF_CFG1                => "1000000000000010",
        RXDFE_KH_CFG0                => "0000000000000000",
        RXDFE_KH_CFG1                => "1000000000000000",
        RXDFE_KH_CFG2                => "0010011000010011",
        RXDFE_KH_CFG3                => "0100000100011100",
        RXDFE_OS_CFG0                => "0000000000000000",
        RXDFE_OS_CFG1                => "1000000000000010",
        RXDFE_PWR_SAVING             => '1',
        RXDFE_UT_CFG0                => "0000000000000000",
        RXDFE_UT_CFG1                => "0000000000000011",
        RXDFE_UT_CFG2                => "0000000000000000",
        RXDFE_VP_CFG0                => "0000000000000000",
        RXDFE_VP_CFG1                => "1000000000110011",
        RXDLY_CFG                    => "0000000000010000",
        RXDLY_LCFG                   => "0000000000110000",
        RXELECIDLE_CFG               => "SIGCFG_4",
        RXGBOX_FIFO_INIT_RD_ADDR     => 4,
        RXGEARBOX_EN                 => "FALSE",
        RXISCANRESET_TIME            => "00001",
        RXLPM_CFG                    => "0000000000000000",
        RXLPM_GC_CFG                 => "1000000000000000",
        RXLPM_KH_CFG0                => "0000000000000000",
        RXLPM_KH_CFG1                => "0000000000000010",
        RXLPM_OS_CFG0                => "0000000000000000",
        RXLPM_OS_CFG1                => "1000000000000010",
        RXOOB_CFG                    => "000000110",
        RXOOB_CLK_CFG                => "PMA",
        RXOSCALRESET_TIME            => "00011",
        RXOUT_DIV                    => pll_mult_div_config_c.D,
        RXPCSRESET_TIME              => "00011",
        RXPHBEACON_CFG               => "0000000000000000",
        RXPHDLY_CFG                  => "0010000001110000",
        RXPHSAMP_CFG                 => "0010000100000000",
        RXPHSLIP_CFG                 => "1001100100110011",
        RXPH_MONITOR_SEL             => "00000",
        RXPI_AUTO_BW_SEL_BYPASS      => '0',
        RXPI_CFG0                    => "0001001100000000",
        RXPI_CFG1                    => "0000000011111101",
        RXPI_LPM                     => '0',
        RXPI_SEL_LC                  => "00",
        RXPI_STARTCODE               => "00",
        RXPI_VREFSEL                 => '0',
        RXPMACLK_SEL                 => "DATA",
        RXPMARESET_TIME              => "00011",
        RXPRBS_ERR_LOOPBACK          => '0',
        RXPRBS_LINKACQ_CNT           => 15,
        RXREFCLKDIV2_SEL             => '0',
        RXSLIDE_AUTO_WAIT            => 7,
        RXSLIDE_MODE                 => "OFF",
        RXSYNC_MULTILANE             => '0',
        RXSYNC_OVRD                  => '0',
        RXSYNC_SKIP_DA               => '1',
        RX_AFE_CM_EN                 => '0',
        RX_BIAS_CFG0                 => "0001010101010100",
        RX_BUFFER_CFG                => "000000",
        RX_CAPFF_SARC_ENB            => '0',
        RX_CLK25_DIV                 => 5,
        RX_CLKMUX_EN                 => '1',
        RX_CLK_SLIP_OVRD             => "00000",
        RX_CM_BUF_CFG                => "1010",
        RX_CM_BUF_PD                 => '0',
        RX_CM_SEL                    => 3,
        RX_CM_TRIM                   => 10,
        RX_CTLE3_LPF                 => "11111111",
        RX_DATA_WIDTH                => data_width_config_c.internal_width,
        RX_DDI_SEL                   => "000000",
        RX_DEFER_RESET_BUF_EN        => "TRUE",
        RX_DEGEN_CTRL                => "011",
        RX_DFELPM_CFG0               => 6,
        RX_DFELPM_CFG1               => '1',
        RX_DFELPM_KLKH_AGC_STUP_EN   => '1',
        RX_DFE_AGC_CFG0              => "10",
        RX_DFE_AGC_CFG1              => 4,
        RX_DFE_KL_LPM_KH_CFG0        => 1,
        RX_DFE_KL_LPM_KH_CFG1        => 4,
        RX_DFE_KL_LPM_KL_CFG0        => "01",
        RX_DFE_KL_LPM_KL_CFG1        => 4,
        RX_DFE_LPM_HOLD_DURING_EIDLE => '0',
        RX_DISPERR_SEQ_MATCH         => "TRUE",
        RX_DIV2_MODE_B               => '0',
        RX_DIVRESET_TIME             => "00001",
        RX_EN_CTLE_RCAL_B            => '0',
        RX_EN_HI_LR                  => '1',
        RX_EXT_RL_CTRL               => "000000000",
        RX_EYESCAN_VS_CODE           => "0000000",
        RX_EYESCAN_VS_NEG_DIR        => '0',
        RX_EYESCAN_VS_RANGE          => "00",
        RX_EYESCAN_VS_UT_SIGN        => '0',
        RX_FABINT_USRCLK_FLOP        => '0',
        RX_INT_DATAWIDTH             => 0,  -- FIXME: modify with config
        RX_PMA_POWER_SAVE            => '0',
        RX_PMA_RSV0                  => "0000000000000000",
        RX_PROGDIV_CFG               => 0.0,
        RX_PROGDIV_RATE              => "0000000000000001",
        RX_RESLOAD_CTRL              => "0000",
        RX_RESLOAD_OVRD              => '0',
        RX_SAMPLE_PERIOD             => "111",
        RX_SIG_VALID_DLY             => 11,
        RX_SUM_DFETAPREP_EN          => '0',
        RX_SUM_IREF_TUNE             => "0100",
        RX_SUM_RESLOAD_CTRL          => "0011",
        RX_SUM_VCMTUNE               => "0110",
        RX_SUM_VCM_OVWR              => '0',
        RX_SUM_VREF_TUNE             => "100",
        RX_TUNE_AFE_OS               => "00",
        RX_VREG_CTRL                 => "101",
        RX_VREG_PDB                  => '1',
        RX_WIDEMODE_CDR              => "00",
        RX_WIDEMODE_CDR_GEN3         => "00",
        RX_WIDEMODE_CDR_GEN4         => "01",
        RX_XCLK_SEL                  => "RXDES",
        RX_XMODE_SEL                 => '0',
        SAMPLE_CLK_PHASE             => '0',
        SAS_12G_MODE                 => '0',
        SATA_BURST_SEQ_LEN           => "1111",
        SATA_BURST_VAL               => "100",
        SATA_CPLL_CFG                => "VCO_3000MHZ",
        SATA_EIDLE_VAL               => "100",
        SHOW_REALIGN_COMMA           => "TRUE",
        SIM_DEVICE                   => "ULTRASCALE_PLUS",
        SIM_MODE                     => "FAST",
        SIM_RECEIVER_DETECT_PASS     => "TRUE",
        SIM_RESET_SPEEDUP            => "TRUE",
        SIM_TX_EIDLE_DRIVE_LEVEL     => "Z",
        SRSTMODE                     => '0',
        TAPDLY_SET_TX                => "00",
        TEMPERATURE_PAR              => "0010",
        TERM_RCAL_CFG                => "100001000010001",
        TERM_RCAL_OVRD               => "000",
        TRANS_TIME_RATE              => "00001110",
        TST_RSV0                     => "00000000",
        TST_RSV1                     => "00000000",
        TXBUF_EN                     => "TRUE",
        TXBUF_RESET_ON_RATE_CHANGE   => "TRUE",
        TXDLY_CFG                    => "1000000000010000",
        TXDLY_LCFG                   => "0000000000110000",
        TXDRVBIAS_N                  => "1010",
        TXFIFO_ADDR_CFG              => "LOW",
        TXGBOX_FIFO_INIT_RD_ADDR     => 4,
        TXGEARBOX_EN                 => "FALSE",
        TXOUT_DIV                    => pll_mult_div_config_c.D,
        TXPCSRESET_TIME              => "00011",
        TXPHDLY_CFG0                 => "0110000001110000",
        TXPHDLY_CFG1                 => "0000000000001111",
        TXPH_CFG                     => "0000011100100011",
        TXPH_CFG2                    => "0000000000000000",
        TXPH_MONITOR_SEL             => "00000",
        TXPI_CFG                     => "0000001111011111",
        TXPI_CFG0                    => "00",
        TXPI_CFG1                    => "00",
        TXPI_CFG2                    => "00",
        TXPI_CFG3                    => '1',
        TXPI_CFG4                    => '1',
        TXPI_CFG5                    => "000",
        TXPI_GRAY_SEL                => '0',
        TXPI_INVSTROBE_SEL           => '0',
        TXPI_LPM                     => '0',
        TXPI_PPM                     => '0',
        TXPI_PPMCLK_SEL              => "TXUSRCLK2",
        TXPI_PPM_CFG                 => "00000000",
        TXPI_SYNFREQ_PPM             => "001",
        TXPI_VREFSEL                 => '0',
        TXPMARESET_TIME              => "00011",
        TXREFCLKDIV2_SEL             => '0',
        TXSYNC_MULTILANE             => '0',
        TXSYNC_OVRD                  => '0',
        TXSYNC_SKIP_DA               => '0',
        TX_CLK25_DIV                 => 5,
        TX_CLKMUX_EN                 => '1',
        TX_DATA_WIDTH                => data_width_config_c.internal_width,
        TX_DCC_LOOP_RST_CFG          => "0000000000000100",
        TX_DEEMPH0                   => "000000",
        TX_DEEMPH1                   => "000000",
        TX_DEEMPH2                   => "000000",
        TX_DEEMPH3                   => "000000",
        TX_DIVRESET_TIME             => "00001",
        TX_DRIVE_MODE                => "DIRECT",
        TX_DRVMUX_CTRL               => 2,
        TX_EIDLE_ASSERT_DELAY        => "100",
        TX_EIDLE_DEASSERT_DELAY      => "011",
        TX_FABINT_USRCLK_FLOP        => '0',
        TX_FIFO_BYP_EN               => '0',
        TX_IDLE_DATA_ZERO            => '0',
        TX_INT_DATAWIDTH             => 0,  -- FIXME: add to config
        TX_LOOPBACK_DRIVE_HIZ        => "FALSE",
        TX_MAINCURSOR_SEL            => '0',
        TX_MARGIN_FULL_0             => "1011111",
        TX_MARGIN_FULL_1             => "1011110",
        TX_MARGIN_FULL_2             => "1011100",
        TX_MARGIN_FULL_3             => "1011010",
        TX_MARGIN_FULL_4             => "1011000",
        TX_MARGIN_LOW_0              => "1000110",
        TX_MARGIN_LOW_1              => "1000101",
        TX_MARGIN_LOW_2              => "1000011",
        TX_MARGIN_LOW_3              => "1000010",
        TX_MARGIN_LOW_4              => "1000000",
        TX_PHICAL_CFG0               => "0000000000000000",
        TX_PHICAL_CFG1               => "0111111000000000",
        TX_PHICAL_CFG2               => "0000001000000001",
        TX_PI_BIASSET                => 0,
        TX_PI_IBIAS_MID              => "00",
        TX_PMADATA_OPT               => '0',
        TX_PMA_POWER_SAVE            => '0',
        TX_PMA_RSV0                  => "0000000000001000",
        TX_PREDRV_CTRL               => 2,
        TX_PROGCLK_SEL               => "PREPI",
        TX_PROGDIV_CFG               => 0.0,
        TX_PROGDIV_RATE              => "0000000000000001",
        TX_QPI_STATUS_EN             => '0',
        TX_RXDETECT_CFG              => "00000000110010",
        TX_RXDETECT_REF              => 4,
        TX_SAMPLE_PERIOD             => "111",
        TX_SARC_LPBK_ENB             => '0',
        TX_SW_MEAS                   => "00",
        TX_VREG_CTRL                 => "000",
        TX_VREG_PDB                  => '0',
        TX_VREG_VREFSEL              => "00",
        TX_XCLK_SEL                  => "TXOUT",
        USB_BOTH_BURST_IDLE          => '0',
        USB_BURSTMAX_U3WAKE          => "1111111",
        USB_BURSTMIN_U3WAKE          => "1100011",
        USB_CLK_COR_EQ_EN            => '0',
        USB_EXT_CNTL                 => '1',
        USB_IDLEMAX_POLLING          => "1010111011",
        USB_IDLEMIN_POLLING          => "0100101011",
        USB_LFPSPING_BURST           => "000000101",
        USB_LFPSPOLLING_BURST        => "000110001",
        USB_LFPSPOLLING_IDLE_MS      => "000000100",
        USB_LFPSU1EXIT_BURST         => "000011101",
        USB_LFPSU2LPEXIT_BURST_MS    => "001100011",
        USB_LFPSU3WAKE_BURST_MS      => "111110011",
        USB_LFPS_TPERIOD             => "0011",
        USB_LFPS_TPERIOD_ACCURATE    => '1',
        USB_MODE                     => '0',
        USB_PCIE_ERR_REP_DIS         => '0',
        USB_PING_SATA_MAX_INIT       => 21,
        USB_PING_SATA_MIN_INIT       => 12,
        USB_POLL_SATA_MAX_BURST      => 8,
        USB_POLL_SATA_MIN_BURST      => 4,
        USB_RAW_ELEC                 => '0',
        USB_RXIDLE_P0_CTRL           => '1',
        USB_TXIDLE_TUNE_ENABLE       => '1',
        USB_U1_SATA_MAX_WAKE         => 7,
        USB_U1_SATA_MIN_WAKE         => 4,
        USB_U2_SAS_MAX_COM           => 64,
        USB_U2_SAS_MIN_COM           => 36,
        USE_PCS_CLK_PHASE_SEL        => '0',
        Y_ALL_MODE                   => '0'
        )
      port map
        (
        -- primitive wrapper parameters which specify GTHE4_CHANNEL primitive input port default driver values
        CDRSTEPDIR           => '0',
        CDRSTEPSQ            => '0',
        CDRSTEPSX            => '0',
        CFGRESET             => '0',
        CLKRSVD0             => '0',
        CLKRSVD1             => '0',
        CPLLFREQLOCK         => '0',
        CPLLLOCKDETCLK       => '0',
        CPLLLOCKEN           => '1',
        CPLLPD               => s_pll_pd,
        CPLLREFCLKSEL        => "001",  --FIXME make general depending on refclk_vec
        CPLLRESET            => '0',
        DMONFIFORESET        => '0',
        DMONITORCLK          => '0',
        DRPADDR              => s_drp_addr,
        DRPCLK               => s_stableclk,
        DRPDI                => s_drp_data_in,
        DRPEN                => s_drp_en,
        DRPRST               => '0',
        DRPWE                => s_drp_wr,
        EYESCANRESET         => '0',
        EYESCANTRIGGER       => '0',
        FREQOS               => '0',
        GTGREFCLK            => '0',
        GTHRXN               => lane_rx_i(lane_idx).n,
        GTHRXP               => lane_rx_i(lane_idx).p,
        GTNORTHREFCLK0       => s_refclk_vec(clock_id("gtnorthrefclk0")),
        GTNORTHREFCLK1       => s_refclk_vec(clock_id("gtnorthrefclk1")),
        GTREFCLK0            => s_refclk_vec(clock_id("gtrefclk0")),
        GTREFCLK1            => s_refclk_vec(clock_id("gtrefclk1")),
        GTRSVD               => (others => '0'),
        GTRXRESET            => s_gth_rx_rst,
        GTRXRESETSEL         => '0',
        GTSOUTHREFCLK0       => s_refclk_vec(clock_id("gtsouthrefclk0")),
        GTSOUTHREFCLK1       => s_refclk_vec(clock_id("gtsouthrefclk1")),
        GTTXRESET            => s_gth_tx_rst,
        GTTXRESETSEL         => '0',
        INCPCTRL             => '0',
        LOOPBACK             => loopback_config_c,
        PCIEEQRXEQADAPTDONE  => '0',
        PCIERSTIDLE          => '0',
        PCIERSTTXSYNCSTART   => '0',
        PCIEUSERRATEDONE     => '0',
        PCSRSVDIN            => (others => '0'),
        QPLL0CLK             => '0',
        QPLL0FREQLOCK        => '0',
        QPLL0REFCLK          => '0',
        QPLL1CLK             => '0',
        QPLL1FREQLOCK        => '0',
        QPLL1REFCLK          => '0',
        RESETOVRD            => '0',
        RX8B10BEN            => '1',
        RXAFECFOKEN          => '1',
        RXBUFRESET           => '0',
        RXCDRFREQRESET       => '0',
        RXCDRHOLD            => s_cdr_hold,
        RXCDROVRDEN          => '0',
        RXCDRRESET           => '0',
        RXCHBONDEN           => '0',
        RXCHBONDI            => (others => '0'),
        RXCHBONDLEVEL        => (others => '0'),
        RXCHBONDMASTER       => '0',
        RXCHBONDSLAVE        => '0',
        RXCKCALRESET         => '0',
        RXCKCALSTART         => (others => '0'),
        RXCOMMADETEN         => '1',
        RXDFEAGCCTRL         => "01",
        RXDFEAGCHOLD         => '0',
        RXDFEAGCOVRDEN       => '0',
        RXDFECFOKFCNUM       => "1101",
        RXDFECFOKFEN         => '0',
        RXDFECFOKFPULSE      => '0',
        RXDFECFOKHOLD        => '0',
        RXDFECFOKOVREN       => '0',
        RXDFEKHHOLD          => '0',
        RXDFEKHOVRDEN        => '0',
        RXDFELFHOLD          => '0',
        RXDFELFOVRDEN        => '0',
        RXDFELPMRESET        => '0',
        RXDFETAP10HOLD       => '0',
        RXDFETAP10OVRDEN     => '0',
        RXDFETAP11HOLD       => '0',
        RXDFETAP11OVRDEN     => '0',
        RXDFETAP12HOLD       => '0',
        RXDFETAP12OVRDEN     => '0',
        RXDFETAP13HOLD       => '0',
        RXDFETAP13OVRDEN     => '0',
        RXDFETAP14HOLD       => '0',
        RXDFETAP14OVRDEN     => '0',
        RXDFETAP15HOLD       => '0',
        RXDFETAP15OVRDEN     => '0',
        RXDFETAP2HOLD        => '0',
        RXDFETAP2OVRDEN      => '0',
        RXDFETAP3HOLD        => '0',
        RXDFETAP3OVRDEN      => '0',
        RXDFETAP4HOLD        => '0',
        RXDFETAP4OVRDEN      => '0',
        RXDFETAP5HOLD        => '0',
        RXDFETAP5OVRDEN      => '0',
        RXDFETAP6HOLD        => '0',
        RXDFETAP6OVRDEN      => '0',
        RXDFETAP7HOLD        => '0',
        RXDFETAP7OVRDEN      => '0',
        RXDFETAP8HOLD        => '0',
        RXDFETAP8OVRDEN      => '0',
        RXDFETAP9HOLD        => '0',
        RXDFETAP9OVRDEN      => '0',
        RXDFEUTHOLD          => '0',
        RXDFEUTOVRDEN        => '0',
        RXDFEVPHOLD          => '0',
        RXDFEVPOVRDEN        => '0',
        RXDFEXYDEN           => '1',
        RXDLYBYPASS          => '1',
        RXDLYEN              => '0',
        RXDLYOVRDEN          => '0',
        RXDLYSRESET          => '0',
        RXELECIDLEMODE       => "11",
        RXEQTRAINING         => '0',
        RXGEARBOXSLIP        => '0',
        RXLATCLK             => '0',
        RXLPMEN              => '1',
        RXLPMGCHOLD          => '0',
        RXLPMGCOVRDEN        => '0',
        RXLPMHFHOLD          => '0',
        RXLPMHFOVRDEN        => '0',
        RXLPMLFHOLD          => '0',
        RXLPMLFKLOVRDEN      => '0',
        RXLPMOSHOLD          => '0',
        RXLPMOSOVRDEN        => '0',
        RXMCOMMAALIGNEN      => s_mcomma_align_en,
        RXMONITORSEL         => (others => '0'),
        RXOOBRESET           => '0',
        RXOSCALRESET         => '0',
        RXOSHOLD             => '0',
        RXOSOVRDEN           => '0',
        RXOUTCLKSEL          => "001",
        RXPCOMMAALIGNEN      => s_pcomma_align_en,
        RXPCSRESET           => '0',
        RXPD                 => (others => '0'),
        RXPHALIGN            => '0',
        RXPHALIGNEN          => '0',
        RXPHDLYPD            => '1',
        RXPHDLYRESET         => '0',
        RXPHOVRDEN           => '0',
        RXPLLCLKSEL          => (others => '0'),
        RXPMARESET           => '0',
        RXPOLARITY           => '0',
        RXPRBSCNTRESET       => '0',
        RXPRBSSEL            => (others => '0'),
        RXPROGDIVRESET       => '0',
        RXQPIEN              => '0',
        RXRATE               => (others => '0'),
        RXRATEMODE           => '0',
        RXSLIDE              => '0',
        RXSLIPOUTCLK         => '0',
        RXSLIPPMA            => '0',
        RXSYNCALLIN          => '0',
        RXSYNCIN             => '0',
        RXSYNCMODE           => '0',
        RXSYSCLKSEL          => (others => '0'),
        RXTERMINATION        => '0',
        RXUSERRDY            => s_rx_ready,
        RXUSRCLK             => s_txusrclk2_buff,
        RXUSRCLK2            => s_txusrclk2_buff,
        SIGVALIDCLK          => '0',
        TSTIN                => (others => '0'),
        TX8B10BBYPASS        => (others => '0'),
        TX8B10BEN            => '1',
        TXCOMINIT            => '0',
        TXCOMSAS             => '0',
        TXCOMWAKE            => '0',
        TXCTRL0              => (others => '0'),
        TXCTRL1              => (others => '0'),
        TXCTRL2              => s_txctrl2,
        TXDATA               => s_gth_tx_data,
        TXDATAEXTENDRSVD     => (others => '0'),
        TXDCCFORCESTART      => '0',
        TXDCCRESET           => '0',
        TXDEEMPH             => (others => '0'),
        TXDETECTRX           => '0',
        TXDIFFCTRL           => "11000",
        TXDLYBYPASS          => '1',
        TXDLYEN              => '0',
        TXDLYHOLD            => '0',
        TXDLYOVRDEN          => '0',
        TXDLYSRESET          => '0',
        TXDLYUPDOWN          => '0',
        TXELECIDLE           => '0',
        TXHEADER             => (others => '0'),
        TXINHIBIT            => '0',
        TXLATCLK             => '0',
        TXLFPSTRESET         => '0',
        TXLFPSU2LPEXIT       => '0',
        TXLFPSU3WAKE         => '0',
        TXMAINCURSOR         => (others => '0'),
        TXMARGIN             => (others => '0'),
        TXMUXDCDEXHOLD       => '0',
        TXMUXDCDORWREN       => '0',
        TXONESZEROS          => '0',
        TXOUTCLKSEL          => "011",
        TXPCSRESET           => '0',
        TXPD                 => (others => '0'),
        TXPDELECIDLEMODE     => '0',
        TXPHALIGN            => '0',
        TXPHALIGNEN          => '0',
        TXPHDLYPD            => '1',
        TXPHDLYRESET         => '0',
        TXPHDLYTSTCLK        => '0',
        TXPHINIT             => '0',
        TXPHOVRDEN           => '0',
        TXPIPPMEN            => '0',
        TXPIPPMOVRDEN        => '0',
        TXPIPPMPD            => '0',
        TXPIPPMSEL           => '0',
        TXPIPPMSTEPSIZE      => (others => '0'),
        TXPISOPD             => '0',
        TXPLLCLKSEL          => (others => '0'),
        TXPMARESET           => '0',
        TXPOLARITY           => '0',
        TXPOSTCURSOR         => (others => '0'),
        TXPRBSFORCEERR       => '0',
        TXPRBSSEL            => (others => '0'),
        TXPRECURSOR          => (others => '0'),
        TXPROGDIVRESET       => '0',
        TXQPIBIASEN          => '0',
        TXQPIWEAKPUP         => '0',
        TXRATE               => (others => '0'),
        TXRATEMODE           => '0',
        TXSEQUENCE           => (others => '0'),
        TXSWING              => '0',
        TXSYNCALLIN          => '0',
        TXSYNCIN             => '0',
        TXSYNCMODE           => '0',
        TXSYSCLKSEL          => (others => '0'),
        TXUSERRDY            => s_tx_ready,
        TXUSRCLK             => s_txusrclk2_buff,
        TXUSRCLK2            => s_txusrclk2_buff,
        BUFGTCE              => open,
        BUFGTCEMASK          => open,
        BUFGTDIV             => open,
        BUFGTRESET           => open,
        BUFGTRSTMASK         => open,
        CPLLFBCLKLOST        => open,
        CPLLLOCK             => s_pll_locked,
        CPLLREFCLKLOST       => open,
        DMONITOROUT          => open,
        DMONITOROUTCLK       => open,
        DRPDO                => s_drp_data_out,
        DRPRDY               => s_drp_rdy,
        EYESCANDATAERROR     => open,
        GTHTXN               => lane_tx_o(lane_idx).n,
        GTHTXP               => lane_tx_o(lane_idx).p,
        GTPOWERGOOD          => s_gt_power_good,
        GTREFCLKMONITOR      => open,
        PCIERATEGEN3         => open,
        PCIERATEIDLE         => open,
        PCIERATEQPLLPD       => open,
        PCIERATEQPLLRESET    => open,
        PCIESYNCTXSYNCDONE   => open,
        PCIEUSERGEN3RDY      => open,
        PCIEUSERPHYSTATUSRST => open,
        PCIEUSERRATESTART    => open,
        PCSRSVDOUT           => open,
        PHYSTATUS            => open,
        PINRSRVDAS           => open,
        POWERPRESENT         => open,
        RESETEXCEPTION       => open,
        RXBUFSTATUS          => open,
        RXBYTEISALIGNED      => open,
        RXBYTEREALIGN        => open,
        RXCDRLOCK            => open,
        RXCDRPHDONE          => open,
        RXCHANBONDSEQ        => open,
        RXCHANISALIGNED      => open,
        RXCHANREALIGN        => open,
        RXCHBONDO            => open,
        RXCKCALDONE          => open,
        RXCLKCORCNT          => open,
        RXCOMINITDET         => open,
        RXCOMMADET           => open,
        RXCOMSASDET          => open,
        RXCOMWAKEDET         => open,
        RXCTRL0              => s_rxctrl0,
        RXCTRL1              => s_rxctrl1,
        RXCTRL2              => open,
        RXCTRL3              => s_rxctrl3,
        RXDATA               => s_gth_rx_data,
        RXDATAEXTENDRSVD     => open,
        RXDATAVALID          => open,
        RXDLYSRESETDONE      => open,
        RXELECIDLE           => open,
        RXHEADER             => open,
        RXHEADERVALID        => open,
        RXLFPSTRESETDET      => open,
        RXLFPSU2LPEXITDET    => open,
        RXLFPSU3WAKEDET      => open,
        RXMONITOROUT         => open,
        RXOSINTDONE          => open,
        RXOSINTSTARTED       => open,
        RXOSINTSTROBEDONE    => open,
        RXOSINTSTROBESTARTED => open,
        RXOUTCLK             => open,
        RXOUTCLKFABRIC       => open,
        RXOUTCLKPCS          => open,
        RXPHALIGNDONE        => open,
        RXPHALIGNERR         => open,
        RXPMARESETDONE       => s_rx_pma_rst_done,
        RXPRBSERR            => open,
        RXPRBSLOCKED         => open,
        RXPRGDIVRESETDONE    => open,
        RXQPISENN            => open,
        RXQPISENP            => open,
        RXRATEDONE           => open,
        RXRECCLKOUT          => open,
        RXRESETDONE          => open,
        RXSLIDERDY           => open,
        RXSLIPDONE           => open,
        RXSLIPOUTCLKRDY      => open,
        RXSLIPPMARDY         => open,
        RXSTARTOFSEQ         => open,
        RXSTATUS             => open,
        RXSYNCDONE           => open,
        RXSYNCOUT            => open,
        RXVALID              => open,
        TXBUFSTATUS          => open,
        TXCOMFINISH          => open,
        TXDCCDONE            => open,
        TXDLYSRESETDONE      => open,
        TXOUTCLK             => s_tx_out_clock,
        TXOUTCLKFABRIC       => open,
        TXOUTCLKPCS          => open,
        TXPHALIGNDONE        => open,
        TXPHINITDONE         => open,
        TXPMARESETDONE       => s_tx_pma_rst_done,
        TXPRGDIVRESETDONE    => open,
        TXQPISENN            => open,
        TXQPISENP            => open,
        TXRATEDONE           => open,
        TXRESETDONE          => open,
        TXSYNCDONE           => open,
        TXSYNCOUT            => open
      );

  end generate;

  -- FIXME: do something with the APB input bus, maybe nothing for now

end architecture;
