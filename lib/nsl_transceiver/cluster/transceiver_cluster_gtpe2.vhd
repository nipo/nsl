library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_data, nsl_math, nsl_hwdep, nsl_logic, nsl_clocking;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.target.all;
use nsl_transceiver.lane.all;
use nsl_data.text.all;

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

architecture gtpe2 of transceiver_cluster is

  -- Signal declarations --------------------------------------------------------------
  -- Transceiver signals
  signal s_pll_0_out      : std_logic;
  signal s_pll_0_outref   : std_logic;
  signal s_pll_0_locked   : std_logic;
  signal s_pll_reset_done : std_logic;

  -- Clock signals
  signal s_refclk_vec : std_ulogic_vector(0 to 6);  -- 7 total clock signals
                                                    -- to assign
  signal s_stableclk  : std_ulogic;

  -- Helper functions -----------------------------------------------------------------
  -- Reference clock vector builder
  function build_refclk_vec(ids  : integer_vector;
                            clks : std_ulogic_vector)
    return std_ulogic_vector
  is
    variable v : std_ulogic_vector(0 to 6) := (others => '0');
  begin
    for i in ids'range loop
      v(ids(i)) := clks(i);
    end loop;
    return v;
  end function;

  -- PLL multiplier divider types
  -- Refer to UG482 Table 2-7
  subtype M_t is natural range 1 to 2;
  subtype N2_t is natural range 1 to 5;
  subtype N1_t is natural range 4 to 5;
  subtype D_t is natural range 1 to 8;

  type pll_mult_div_t is
  record
    M  : M_t;
    N2 : N2_t;
    N1 : N1_t;
    D  : D_t;
  end record;

  -- PLL multiplier and divider calculator
  function pll_mult_div_assign (line_rate_mhz : natural;
                                pll_vco_mhz   : natural;
                                ref_clk_mhz   : natural)
    return pll_mult_div_t
  is
    variable d          : real;
    variable ratio      : real;
    variable pll_config : pll_mult_div_t;
  begin  -- function pll_mult_div_assign
    -- Check valid PLL VCO frequency
    assert (pll_vco_mhz >= 1600 and pll_vco_mhz <= 3300)
      report "transceiver_cluster/gtpe2: Invalid PLL VCO frequency: GTP transceivers accept a range of 1.6GHz to 3.3GHz"
      severity failure;

    -- Calculate D
    d := (real(pll_vco_mhz) * 2.0) / real(line_rate_mhz);
    assert d = 1.0 or d = 2.0 or d = 4.0 or d = 8.0
      report "transceiver_cluster/gtpe2: Invalid PLL VCO to line rate ratio, valid ratios are 1, 2, 4, or 8"
      severity failure;
    pll_config.D := natural(d);

    -- Calculate PLL to Ref ratio and check valid value
    ratio := real(pll_vco_mhz) / real(ref_clk_mhz);
    assert ratio = 2.0 or ratio = 2.5 or ratio = 4.0 or ratio = 5.0 or ratio = 6.0 or ratio = 7.5 or
      ratio = 8.0 or ratio = 10.0 or ratio = 12.0 or ratio = 12.5 or ratio = 15.0 or ratio = 16.0 or
      ratio = 20.0 or ratio = 25.0
      report "transceiver_cluster/gtpe2: Invalid PLL VCO to reference clock ratio, valid ratios are 2, 2.5, 4, 5, 6, 7.5, 8, 10, 12, 12.5, 15, 16, 20, or 25"
      severity failure;

    -- Assign M, N2, and N1
    if ratio = 2.0 then
      pll_config.M  := 2;
      pll_config.N2 := 1;
      pll_config.N1 := 4;

    elsif ratio = 2.5 then
      pll_config.M  := 2;
      pll_config.N2 := 1;
      pll_config.N1 := 5;

    elsif ratio = 4.0 then
      pll_config.M  := 1;
      pll_config.N2 := 1;
      pll_config.N1 := 4;

    elsif ratio = 5.0 then
      pll_config.M  := 1;
      pll_config.N2 := 1;
      pll_config.N1 := 5;

    elsif ratio = 6.0 then
      pll_config.M  := 2;
      pll_config.N2 := 3;
      pll_config.N1 := 4;

    elsif ratio = 7.5 then
      pll_config.M  := 2;
      pll_config.N2 := 3;
      pll_config.N1 := 5;

    elsif ratio = 8.0 then
      pll_config.M  := 1;
      pll_config.N2 := 2;
      pll_config.N1 := 4;

    elsif ratio = 10.0 then
      pll_config.M  := 1;
      pll_config.N2 := 2;
      pll_config.N1 := 5;

    elsif ratio = 12.0 then
      pll_config.M  := 1;
      pll_config.N2 := 3;
      pll_config.N1 := 4;

    elsif ratio = 12.5 then
      pll_config.M  := 2;
      pll_config.N2 := 5;
      pll_config.N1 := 5;

    elsif ratio = 15.0 then
      pll_config.M  := 1;
      pll_config.N2 := 3;
      pll_config.N1 := 5;

    elsif ratio = 16.0 then
      pll_config.M  := 1;
      pll_config.N2 := 4;
      pll_config.N1 := 4;

    elsif ratio = 20.0 then
      pll_config.M  := 1;
      pll_config.N2 := 5;
      pll_config.N1 := 4;

    elsif ratio = 25.0 then
      pll_config.M  := 1;
      pll_config.N2 := 5;
      pll_config.N1 := 5;

    end if;

    return pll_config;
  end function pll_mult_div_assign;

  constant pll_mult_div_config_c : pll_mult_div_t := pll_mult_div_assign(config_c.lanes(0).line_rate_mbps, config_c.plls(0).target_vco_mhz, config_c.plls(0).ref_clock_mhz);

begin

  assert config_c.lane_count <= 4
    report "transceiver_cluster/gtpe2: GTPE2_CHANNEL primitive can have up to 4 lanes"
    severity failure;
  assert config_c.pll_count <= 2
    report "transceiver_cluster/gtpe2: GTPE2_COMMON exposes at most 2 quad-shared PLLs (PLL0/PLL1)"
    severity failure;
  assert ref_clock_c'length <= 7
    report "transceiver_cluster/gtpe2: GTPE2_CHANNEL exposes at most 7 reference clock inputs (gtrefclk0, gtwestrefclk0, etc.)"
    severity failure;
  assert nsl_transceiver.cluster.is_valid(config_c)
    report "transceiver_cluster/gtpe2: configuration failed target-agnostic consistency check"
    severity failure;

  encoding_check : for lane_idx in 0 to config_c.lane_count-1 generate
    encoding_supported : if config_c.lanes(lane_idx).enabled generate
      assert config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_RAW
          or config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_8B10B
        report "transceiver_cluster/gtpe2: lane encoding not supported by this backend yet"
        severity failure;
      assert config_c.lanes(lane_idx).data_byte_count >= 1
          or config_c.lanes(lane_idx).data_byte_count <= 4
        report "transceiver_cluster/gtpe2: lane data_byte_count must be between >= 1 and <= 4"
        severity failure;
    end generate;
  end generate;

  -- Reference clock source routing. Each ref_clock_i entry is
  -- driven onto the primitive input matching the target-defined
  -- identifier in ref_clock_c(i).
  s_refclk_vec <= build_refclk_vec(ref_clock_c, ref_clock_i);
  s_stableclk  <= s_refclk_vec(clock_id("stableclk"));

  -- GTPE2 Common ----------------------------------------------------------------------
  gtpe2_common_gen : if config_c.lane_count >= 1 generate

    signal s_pll0_rst    : std_logic;
    signal s_pll0_pd     : std_logic;
    signal s_count500val : integer;
    signal s_countdone   : std_logic;

  begin

    -- PLL reset
    s_pll0_rst <= s_countdone;

    count500 : process (s_stableclk, reset_n_i) is
    begin  -- process count500
      if reset_n_i = '0' then
        s_count500val    <= 0;
        s_countdone      <= '0';
        s_pll0_pd        <= '1';
        s_pll_reset_done <= '0';
      elsif rising_edge(s_stableclk) then
        if s_count500val = 50 then
          s_countdone      <= '0';
          s_count500val    <= s_count500val + 1;
          s_pll0_pd        <= '0';
          s_pll_reset_done <= '0';
        elsif s_count500val = 100 then
          s_countdone      <= '1';
          s_count500val    <= s_count500val + 1;
          s_pll0_pd        <= '0';
          s_pll_reset_done <= '0';
        elsif s_count500val = 105 then
          s_countdone      <= '0';
          s_count500val    <= 105;
          s_pll0_pd        <= '0';
          s_pll_reset_done <= '1';
        else
          s_countdone      <= s_countdone;
          s_count500val    <= s_count500val + 1;
          s_pll0_pd        <= s_pll0_pd;
          s_pll_reset_done <= s_pll_reset_done;
        end if;
      end if;
    end process count500;

    gtpe2_common_i : GTPE2_COMMON
      generic map
      (
        -- Simulation attributes
        -- SIM_RESET_SPEEDUP    => WRAPPER_SIM_GTRESET_SPEEDUP,
        -- SIM_PLL0REFCLK_SEL   => SIM_PLL0REFCLK_SEL,
        -- SIM_PLL1REFCLK_SEL   => SIM_PLL1REFCLK_SEL,
        -- SIM_VERSION          => ("2.0"),

        PLL0_FBDIV      => pll_mult_div_config_c.N2,
        PLL0_FBDIV_45   => pll_mult_div_config_c.N1,
        PLL0_REFCLK_DIV => pll_mult_div_config_c.M,
        PLL1_FBDIV      => (1),
        PLL1_FBDIV_45   => (4),
        PLL1_REFCLK_DIV => (1),

        ------------------COMMON BLOCK Attributes---------------
        BIAS_CFG   => (x"0000000000050001"),
        COMMON_CFG => (x"00000000"),

        ----------------------------PLL Attributes----------------------------
        PLL0_CFG       => (x"01F03DC"),
        PLL0_DMON_CFG  => ('0'),
        PLL0_INIT_CFG  => (x"00001E"),
        PLL0_LOCK_CFG  => (x"1E8"),
        PLL1_CFG       => (x"01F03DC"),
        PLL1_DMON_CFG  => ('0'),
        PLL1_INIT_CFG  => (x"00001E"),
        PLL1_LOCK_CFG  => (x"1E8"),
        PLL_CLKOUT_CFG => (x"00"),

        ----------------------------Reserved Attributes----------------------------
        RSVD_ATTR0 => (x"0000"),
        RSVD_ATTR1 => (x"0000")


        )
      port map
      (
        DMONITOROUT       => open,
        ------------- Common Block  - Dynamic Reconfiguration Port (DRP) -----------
        DRPADDR           => "00000000",
        DRPCLK            => '0',
        DRPDI             => x"0000",
        DRPDO             => open,
        DRPEN             => '0',
        DRPRDY            => open,
        DRPWE             => '0',
        ----------------- Common Block - GTPE2_COMMON Clocking Ports ---------------
        GTEASTREFCLK0     => s_refclk_vec(clock_id("gteastrefclk0")),
        GTEASTREFCLK1     => s_refclk_vec(clock_id("gteastrefclk1")),
        GTGREFCLK1        => '0',
        GTREFCLK0         => s_refclk_vec(clock_id("gtrefclk0")),
        GTREFCLK1         => s_refclk_vec(clock_id("gtrefclk1")),
        GTWESTREFCLK0     => s_refclk_vec(clock_id("gtwestrefclk0")),
        GTWESTREFCLK1     => s_refclk_vec(clock_id("gtwestrefclk1")),
        PLL0OUTCLK        => s_pll_0_out,
        PLL0OUTREFCLK     => s_pll_0_outref,
        PLL1OUTCLK        => open,
        PLL1OUTREFCLK     => open,
        -------------------------- Common Block - PLL Ports ------------------------
        PLL0FBCLKLOST     => open,
        PLL0LOCK          => s_pll_0_locked,
        PLL0LOCKDETCLK    => '0',
        PLL0LOCKEN        => '1',
        PLL0PD            => s_pll0_pd,
        PLL0REFCLKLOST    => open,
        PLL0REFCLKSEL     => "001",
        PLL0RESET         => s_pll0_rst,
        PLL1FBCLKLOST     => open,
        PLL1LOCK          => open,
        PLL1LOCKDETCLK    => '0',
        PLL1LOCKEN        => '1',
        PLL1PD            => '1',
        PLL1REFCLKLOST    => open,
        PLL1REFCLKSEL     => "001",
        PLL1RESET         => '0',
        ---------------------------- Common Block - Ports --------------------------
        BGRCALOVRDENB     => '1',
        GTGREFCLK0        => '0',
        PLLRSVD1          => "0000000000000000",
        PLLRSVD2          => "00000",
        REFCLKOUTMONITOR0 => open,
        REFCLKOUTMONITOR1 => open,
        ------------------------ Common Block - RX AFE Ports -----------------------
        PMARSVDOUT        => open,
        --------------------------------- QPLL Ports -------------------------------
        BGBYPASSB         => '1',
        BGMONITORENB      => '1',
        BGPDB             => '1',
        BGRCALOVRD        => "11111",
        PMARSVD           => "00000000",
        RCALENB           => '1'

        );
  end generate;

  -- Lanes --------------------------------------------------------------------------------
  instantiate_lanes : for lane_idx in 0 to config_c.lane_count-1 generate

    signal s_gtp_rst      : std_logic;
    signal s_drp_data_in  : std_logic_vector(15 downto 0);
    signal s_drp_data_out : std_logic_vector(15 downto 0);
    signal s_drp_addr     : std_logic_vector(8 downto 0);
    signal s_drp_en       : std_logic;
    signal s_drp_wr       : std_logic;
    signal s_drp_rdy      : std_logic;
    signal s_pma_rst_done : std_logic;

    signal s_txoutclk_buff         : std_ulogic;
    signal s_parallel_clock        : std_ulogic;
    signal s_parallel_clock_buff   : std_ulogic;
    signal s_parallel_reset_sync_n : std_ulogic;
    signal s_txusrclk2             : std_ulogic;
    signal s_txusrclk2_buff        : std_ulogic;

    signal s_rx_ready      : std_logic;
    signal s_tx_ready      : std_logic;
    signal s_gtp_rx_data   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_gtp_tx_data   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_tx_out_clock  : std_logic;
    signal s_rxchariscomma : std_logic_vector(3 downto 0);
    signal s_rxcharisk     : std_logic_vector(3 downto 0);
    signal s_rxdisperr     : std_logic_vector(3 downto 0);
    signal s_rxcodeerr     : std_logic_vector(3 downto 0);
    signal s_txcharisk     : std_logic_vector(3 downto 0);

    signal s_pcomma_align_en : std_logic;
    signal s_mcomma_align_en : std_logic;
    signal s_cdr_hold        : std_logic;

    signal s_align_ready : std_ulogic_vector(0 downto 0);
    
    type reset_state_t is (
      ST_RESET,
      ST_WAIT_PLL,
      ST_WAIT_PMA_LOW,
      ST_READ_DRP,
      ST_READ_WAIT,
      ST_WRITE_DRP,
      ST_WRITE_WAIT,
      ST_WAIT_PMA_LOW2,
      ST_WAIT_PMA_HIGH,
      ST_WAIT_PMA_FALL,
      ST_RESTORE_DRP,
      ST_RESTORE_WAIT,
      ST_DONE);

    type regs_t is
    record
      state   : reset_state_t;
      gtp_rst : std_ulogic;
      drp_en  : std_ulogic;
      drp_wr  : std_ulogic;
      drp_val : std_ulogic_vector(15 downto 0);
      drp_out : std_ulogic_vector(15 downto 0);
    end record;

    signal r, rin : regs_t;

    -- Loopback configuration function, see Table 2-27 UG482
    function loopback_configure (config : nsl_transceiver.lane.loopback_mode_t)
      return std_logic_vector
    is
      variable return_val : std_logic_vector(2 downto 0) := (others => '0');
    begin
      case config is
        when nsl_transceiver.lane.LOOPBACK_NONE         => return_val := "000";
        when nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA => return_val := "010";
        when nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS => return_val := "001";
        when nsl_transceiver.lane.LOOPBACK_FAR_END_PMA  => return_val := "100";
        when nsl_transceiver.lane.LOOPBACK_FAR_END_PCS  => return_val := "110";
      end case;
      return return_val;
    end function;

    type data_width_t is
    record
      internal_width  : natural;
      interface_width : natural;
    end record;

    -- Data width calculation, see Table 3-4 UG482
    function determine_data_width (byte_count : natural)
      return data_width_t
    is
      variable return_val : data_width_t;
    begin
      if byte_count <= 2 then
        return_val.internal_width  := 20;
        return_val.interface_width := 16;
      elsif byte_count >= 3 then
        return_val.internal_width  := 40;
        return_val.interface_width := 32;
      end if;
      return return_val;
    end function;

    subtype loopback_config_t is std_logic_vector(2 downto 0);
    constant loopback_config_c : loopback_config_t := loopback_configure(config_c.lanes(lane_idx).loopback);

    constant data_byte_count_c   : natural      := config_c.lanes(lane_idx).data_byte_count;
    constant data_width_config_c : data_width_t := determine_data_width(data_byte_count_c);
    constant data_bit_count_c    : natural      := config_c.lanes(lane_idx).data_byte_count * 8;
    constant data_width_ratio_c  : natural      := (data_bit_count_c) / data_width_config_c.interface_width;

    signal s_rx_data_to_adapter   : std_ulogic_vector(data_bit_count_c - 1 downto 0) := (others => '0');
    signal s_tx_data_from_adapter : std_ulogic_vector(data_bit_count_c - 1 downto 0) := (others => '0');

  begin

    -- TX and RX Data ------------------------------------------------------------
    packunpack : for i in 0 to data_byte_count_c - 1 generate
      s_tx_data_from_adapter(8*i + 7 downto 8*i) <= tx_m_i(lane_idx).data(i);
      rx_m_o(lane_idx).data(i)                   <= s_rx_data_to_adapter(8*i + 7 downto 8*i);
    end generate;

    -- GTP reset -----------------------------------------------------------------
    s_gtp_rst     <= r.gtp_rst;
    s_drp_data_in <= std_logic_vector(r.drp_out);
    s_drp_addr    <= B"000010001";
    s_drp_en      <= r.drp_en;
    s_drp_wr      <= r.drp_wr;
    s_rx_ready    <= s_pll_reset_done;
    s_tx_ready    <= s_rx_ready;

    reg : process(reset_n_i, s_stableclk)
    begin
      if rising_edge(s_stableclk) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition : process(r, s_drp_data_out, s_drp_rdy, s_pll_0_locked,
                         s_pll_reset_done, s_pma_rst_done) is

    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state   <= ST_WAIT_PLL;
          rin.gtp_rst <= '0';
          rin.drp_en  <= '0';
          rin.drp_wr  <= '0';
          rin.drp_val <= (others => '0');
          rin.drp_out <= (others => '0');
        when ST_WAIT_PLL =>
          rin.gtp_rst <= '0';
          if s_pll_0_locked = '1' and s_pll_reset_done = '1' then
            rin.state <= ST_WAIT_PMA_LOW;
          end if;
        when ST_WAIT_PMA_LOW =>
          rin.gtp_rst <= '1';
          if s_pma_rst_done = '0' then
            rin.state <= ST_READ_DRP;
          end if;
        when ST_READ_DRP =>
          rin.drp_en <= '1';
          rin.drp_wr <= '0';
          rin.state  <= ST_READ_WAIT;
        when ST_READ_WAIT =>
          rin.drp_en <= '0';
          rin.drp_wr <= '0';
          if s_drp_rdy = '1' then
            rin.drp_val <= std_ulogic_vector(s_drp_data_out);
            rin.state   <= ST_WRITE_DRP;
          end if;
        when ST_WRITE_DRP =>
          rin.drp_en  <= '1';
          rin.drp_wr  <= '1';
          rin.drp_out <= r.drp_val(15 downto 12) & '0' & r.drp_val(10 downto 0);
          rin.state   <= ST_WRITE_WAIT;
        when ST_WRITE_WAIT =>
          rin.drp_en <= '0';
          rin.drp_wr <= '0';
          if s_drp_rdy = '1' then
            rin.state <= ST_WAIT_PMA_LOW2;
          end if;
        when ST_WAIT_PMA_LOW2 =>
          rin.drp_en  <= '0';
          rin.drp_wr  <= '0';
          rin.gtp_rst <= '0';
          if s_pma_rst_done = '0' then
            rin.state <= ST_WAIT_PMA_HIGH;
          end if;
        when ST_WAIT_PMA_HIGH =>
          if s_pma_rst_done = '1' then
            rin.state <= ST_WAIT_PMA_FALL;
          end if;
        when ST_WAIT_PMA_FALL =>
          if s_pma_rst_done = '0' then
            rin.state <= ST_RESTORE_DRP;
          end if;
        when ST_RESTORE_DRP =>
          rin.drp_en  <= '1';
          rin.drp_wr  <= '1';
          rin.drp_out <= r.drp_val;
          rin.state   <= ST_RESTORE_WAIT;
        when ST_RESTORE_WAIT =>
          rin.drp_en <= '0';
          rin.drp_wr <= '0';
          if s_drp_rdy = '1' then
            rin.state <= ST_DONE;
          end if;
        when ST_DONE =>
          rin.drp_en <= '0';
          rin.drp_wr <= '0';
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
      signal s_gtp_tx_data_stdu : std_ulogic_vector(data_width_config_c.interface_width - 1 downto 0);

    begin

      rx_m_o(lane_idx).status(data_byte_count_c * 1 - 1 downto data_byte_count_c * 0) <= s_rx_charisk_gear;
      rx_m_o(lane_idx).status(data_byte_count_c * 2 - 1 downto data_byte_count_c * 1) <= s_rx_disperr_gear;
      rx_m_o(lane_idx).status(data_byte_count_c * 3 - 1 downto data_byte_count_c * 2) <= s_rx_codeerr_gear;
      s_tx_charisk_gear                                                               <= tx_m_i(lane_idx).control(data_byte_count_c - 1 downto 0);
      s_txcharisk                                                                     <= std_logic_vector(s_txcharisk_vec);
      s_gtp_tx_data(data_width_config_c.interface_width - 1 downto 0)                 <= std_logic_vector(s_gtp_tx_data_stdu);

      gearbox_datafromrx : nsl_logic.gearbox.gearbox_c2c
        generic map (
          input_width_c   => data_width_config_c.interface_width,
          output_width_c  => data_bit_count_c,
          left_to_right_c => false
          )
        port map (
          clock_i   => s_parallel_clock_buff,
          reset_n_i => s_parallel_reset_sync_n,
          in_i      => std_ulogic_vector(s_gtp_rx_data(data_width_config_c.interface_width - 1 downto 0)),
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
          out_o     => s_gtp_tx_data_stdu
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

    not_loopback : if config_c.lanes(lane_idx).loopback = nsl_transceiver.lane.LOOPBACK_NONE generate
      -- Alignment done
      s_pcomma_align_en                                                               <= not(s_align_ready(0));
      s_mcomma_align_en                                                               <= not(s_align_ready(0));
      s_cdr_hold                                                                      <= s_align_ready(0);
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

    loopback_align_gen : if config_c.lanes(lane_idx).loopback /= nsl_transceiver.lane.LOOPBACK_NONE generate
      s_pcomma_align_en                                                               <= '1';
      s_mcomma_align_en                                                               <= '1';
      s_cdr_hold                                                                      <= '1';
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

      bufg_inst : nsl_clocking.distribution.clock_buffer
        port map (
          clock_i => s_tx_out_clock,
          clock_o => s_txoutclk_buff
          );    

      s_domain_a_pll_reset <= not s_pma_rst_done;

      mmcm_gen : if data_width_ratio_c /= 1 generate

        type params is
        record
          vco_freq    : integer;
          fin_factor  : integer;
          fout_factor : integer;
        end record;

        type pll_variant is (
          S6_PLL,
          S7_MMCM,
          S7_PLL,
          S6_DCM
          );

        type constraints is
        record
          fmin, fmax                    : integer;
          in_factor_max, out_factor_max : integer;
          mode                          : string(1 to 3);
        end record;

        function constraints_get(mode : pll_variant) return constraints
        is
          variable ret : nsl_hwdep.xc7_config.pll_constraints;
        begin
          if mode = S7_MMCM then
            ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.MMCM);
          elsif mode = S7_PLL then
            ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.PLL);
          else
            report "Unsupported mode" severity failure;
          end if;

          return constraints'(
            fmin           => ret.fmin,
            fmax           => ret.fmax,
            in_factor_max  => ret.in_factor_max,
            out_factor_max => ret.out_factor_max,
            mode           => ret.mode
            );
        end function;
        
        function pll_params_calc(fin, fout : integer;
                                 mode      : pll_variant) return params
        is
          constant bounds             : constraints := constraints_get(mode);
          variable freq_lcm, vco_mult : integer;
          variable ret                : params;
        begin
          freq_lcm := nsl_math.arith.lcm(fin, fout);

          vco_mult := integer(trunc(realmin(
            real(bounds.fmax) / real(freq_lcm),
            real(bounds.in_factor_max) * real(fin) / real(freq_lcm)
            )));
          if vco_mult = 0 then
            vco_mult := 1;
          end if;

          ret.vco_freq    := freq_lcm * vco_mult;
          ret.fin_factor  := ret.vco_freq / fin;
          ret.fout_factor := ret.vco_freq / fout;

          report "Synthesizing " & bounds.mode & ", "
            & "fin=" & to_string(real(fin) / 1.0e6) & " MHz, "
            & "fout=" & to_string(real(fout) / 1.0e6) & "MHz"
            severity note;
          report "Freq lcm=" & to_string(real(freq_lcm) / 1.0e6) & "MHz, "
            & "vco_freq=" & to_string(real(ret.vco_freq) / 1.0e6) & "MHz "
            & "(min=" & to_string(real(bounds.fmin) / 1.0e6) & "MHz, "
            & "max=" & to_string(real(bounds.fmax) / 1.0e6) & "MHz), "
            & "= fin * " & to_string(ret.fin_factor) & ", "
            & "= fout * " & to_string(ret.fout_factor)
            severity note;

          assert bounds.fmin <= ret.vco_freq and ret.vco_freq <= bounds.fmax
                                report "Needed VCO frequency is out of range"
                                severity failure;

          assert ret.fout_factor <= bounds.out_factor_max
                                    report "Clock output frequency is out of range"
                                    severity failure;

          assert ret.fin_factor <= bounds.in_factor_max
                                   report "Clock input frequency is out of range"
                                   severity failure;

          return ret;
        end function;

        constant input_hz_c        : natural := config_c.lanes(lane_idx).line_rate_mbps * 50000;
        constant input_period_ns_c : real    := 1.0e9 / real(input_hz_c);
        constant output_hz_c       : natural := config_c.lanes(lane_idx).line_rate_mbps * 100000;

        constant p : params := pll_params_calc(input_hz_c, output_hz_c, S7_MMCM);

        begin
          domain_a_pll_inst : mmcme2_adv
            generic map (
              divclk_divide    => 1,
              clkin1_period    => input_period_ns_c,
              clkfbout_mult_f  => real(p.fin_factor),
              clkout0_divide_f => real(p.fout_factor),
              clkout1_divide   => p.fin_factor,
              ref_jitter1      => 0.125
              )
            port map (
              rst      => s_domain_a_pll_reset,
              clkin1   => s_txoutclk_buff,
              clkin2   => '0',
              clkinsel => '1',

              clkout0 => s_parallel_clock,
              clkout1 => s_txusrclk2,
              locked  => s_domain_a_pll_locked,

              daddr => "0000000",
              dclk  => '0',
              den   => '0',
              di    => x"0000",
              dwe   => '0',

              pwrdwn => '0',

              clkfbin  => s_domain_a_pll_feedback,
              clkfbout => s_domain_a_pll_feedback,

              psclk    => '0',
              psen     => '0',
              psincdec => '0'
              );

          bufg_parclk : nsl_clocking.distribution.clock_buffer
            port map (
              clock_i => s_parallel_clock,
              clock_o => s_parallel_clock_buff
              );

          bufg_txusrclk : nsl_clocking.distribution.clock_buffer
            port map (
              clock_i => s_txusrclk2,
              clock_o => s_txusrclk2_buff
              );

      end generate;

        no_mmcm_gen : if data_width_ratio_c = 1 generate  -- Data width between adapter and transceiver is the same

          -- No MMCM needed
          s_parallel_clock_buff <= s_txoutclk_buff;
          s_txusrclk2_buff      <= s_txoutclk_buff;
          s_domain_a_pll_locked <= s_pll_0_locked;
        
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
    gtpe2_i : GTPE2_CHANNEL
      generic map
      (

        --_______________________ Simulation-Only Attributes ___________________

        -- SIM_RECEIVER_DETECT_PASS   =>      ("TRUE"),
        -- SIM_RESET_SPEEDUP          =>      (GT_SIM_GTRESET_SPEEDUP),
        -- SIM_TX_EIDLE_DRIVE_LEVEL   =>      ("X"),
        -- SIM_VERSION                =>      ("2.0"),


        ------------------RX Byte and Word Alignment Attributes---------------
        ALIGN_COMMA_DOUBLE => ("FALSE"),
        ALIGN_COMMA_ENABLE => ("0001111111"),
        ALIGN_COMMA_WORD   => (2),
        ALIGN_MCOMMA_DET   => ("TRUE"),
        ALIGN_MCOMMA_VALUE => ("1010000011"),
        ALIGN_PCOMMA_DET   => ("TRUE"),
        ALIGN_PCOMMA_VALUE => ("0101111100"),
        SHOW_REALIGN_COMMA => ("TRUE"),
        RXSLIDE_AUTO_WAIT  => (7),
        RXSLIDE_MODE       => ("OFF"),
        RX_SIG_VALID_DLY   => (10),

        ------------------RX 8B/10B Decoder Attributes---------------
        RX_DISPERR_SEQ_MATCH => ("TRUE"),
        DEC_MCOMMA_DETECT    => ("TRUE"),
        DEC_PCOMMA_DETECT    => ("TRUE"),
        DEC_VALID_COMMA_ONLY => ("FALSE"),

        ------------------------RX Clock Correction Attributes----------------------
        CBCC_DATA_SOURCE_SEL => ("DECODED"),
        CLK_COR_SEQ_2_USE    => ("TRUE"),
        CLK_COR_KEEP_IDLE    => ("FALSE"),
        CLK_COR_MAX_LAT      => (36),
        CLK_COR_MIN_LAT      => (33),
        CLK_COR_PRECEDENCE   => ("TRUE"),
        CLK_COR_REPEAT_WAIT  => (0),
        CLK_COR_SEQ_LEN      => (2),
        CLK_COR_SEQ_1_ENABLE => ("1111"),
        CLK_COR_SEQ_1_1      => ("0110111100"),  -- K28.5
        CLK_COR_SEQ_1_2      => ("0001010000"),  -- D16.2
        CLK_COR_SEQ_1_3      => ("0000000000"),
        CLK_COR_SEQ_1_4      => ("0000000000"),
        CLK_CORRECT_USE      => ("TRUE"),
        CLK_COR_SEQ_2_ENABLE => ("1111"),
        CLK_COR_SEQ_2_1      => ("0110111100"),  -- K28.5
        CLK_COR_SEQ_2_2      => ("0011000101"),  -- D5.6
        CLK_COR_SEQ_2_3      => ("0000000000"),
        CLK_COR_SEQ_2_4      => ("0000000000"),

        ------------------------RX Channel Bonding Attributes----------------------
        CHAN_BOND_KEEP_ALIGN   => ("FALSE"),
        CHAN_BOND_MAX_SKEW     => (1),
        CHAN_BOND_SEQ_LEN      => (1),
        CHAN_BOND_SEQ_1_1      => ("0000000000"),
        CHAN_BOND_SEQ_1_2      => ("0000000000"),
        CHAN_BOND_SEQ_1_3      => ("0000000000"),
        CHAN_BOND_SEQ_1_4      => ("0000000000"),
        CHAN_BOND_SEQ_1_ENABLE => ("1111"),
        CHAN_BOND_SEQ_2_1      => ("0000000000"),
        CHAN_BOND_SEQ_2_2      => ("0000000000"),
        CHAN_BOND_SEQ_2_3      => ("0000000000"),
        CHAN_BOND_SEQ_2_4      => ("0000000000"),
        CHAN_BOND_SEQ_2_ENABLE => ("1111"),
        CHAN_BOND_SEQ_2_USE    => ("FALSE"),
        FTS_DESKEW_SEQ_ENABLE  => ("1111"),
        FTS_LANE_DESKEW_CFG    => ("1111"),
        FTS_LANE_DESKEW_EN     => ("FALSE"),

        ---------------------------RX Margin Analysis Attributes----------------------------
        ES_CONTROL     => ("000000"),
        ES_ERRDET_EN   => ("FALSE"),
        ES_EYE_SCAN_EN => ("FALSE"),
        ES_HORZ_OFFSET => (x"010"),
        ES_PMA_CFG     => ("0000000000"),
        ES_PRESCALE    => ("00000"),
        ES_QUALIFIER   => (x"00000000000000000000"),
        ES_QUAL_MASK   => (x"00000000000000000000"),
        ES_SDATA_MASK  => (x"00000000000000000000"),
        ES_VERT_OFFSET => ("000000000"),

        -------------------------FPGA RX Interface Attributes-------------------------
        RX_DATA_WIDTH => data_width_config_c.internal_width,

        ---------------------------PMA Attributes----------------------------
        OUTREFCLK_SEL_INV => ("11"),
        PMA_RSV           => (x"00000333"),
        PMA_RSV2          => (x"00002040"),
        PMA_RSV3          => ("00"),
        PMA_RSV4          => ("0000"),
        RX_BIAS_CFG       => ("0000111100110011"),
        DMONITOR_CFG      => (x"000A00"),
        RX_CM_SEL         => ("11"),
        RX_CM_TRIM        => ("1010"),
        RX_DEBUG_CFG      => ("00000000000000"),
        RX_OS_CFG         => ("0000010000000"),
        TERM_RCAL_CFG     => ("100001000010000"),
        TERM_RCAL_OVRD    => ("000"),
        TST_RSV           => (x"00000000"),
        RX_CLK25_DIV      => (4),
        TX_CLK25_DIV      => (4),
        UCODEER_CLR       => ('0'),

        ---------------------------PCI Express Attributes----------------------------
        PCS_PCIE_EN => ("FALSE"),

        ---------------------------PCS Attributes----------------------------
        PCS_RSVD_ATTR => (x"000000000000"),

        -------------RX Buffer Attributes------------
        RXBUF_ADDR_MODE            => ("FULL"),
        RXBUF_EIDLE_HI_CNT         => ("1000"),
        RXBUF_EIDLE_LO_CNT         => ("0000"),
        RXBUF_EN                   => ("TRUE"),
        RX_BUFFER_CFG              => ("000000"),
        RXBUF_RESET_ON_CB_CHANGE   => ("TRUE"),
        RXBUF_RESET_ON_COMMAALIGN  => ("FALSE"),
        RXBUF_RESET_ON_EIDLE       => ("FALSE"),
        RXBUF_RESET_ON_RATE_CHANGE => ("TRUE"),
        RXBUFRESET_TIME            => ("00001"),
        RXBUF_THRESH_OVFLW         => (61),
        RXBUF_THRESH_OVRD          => ("FALSE"),
        RXBUF_THRESH_UNDFLW        => (8),
        RXDLY_CFG                  => (x"001F"),
        RXDLY_LCFG                 => (x"030"),
        RXDLY_TAP_CFG              => (x"0000"),
        RXPH_CFG                   => (x"C00002"),
        RXPHDLY_CFG                => (x"084020"),
        RXPH_MONITOR_SEL           => ("00000"),
        RX_XCLK_SEL                => ("RXREC"),
        RX_DDI_SEL                 => ("000000"),
        RX_DEFER_RESET_BUF_EN      => ("TRUE"),

        -----------------------CDR Attributes-------------------------

        --For Display Port, HBR/RBR- set RXCDR_CFG=72'h0380008bff40200008

        --For Display Port, HBR2 -   set RXCDR_CFG=72'h038c008bff20200010

        --For SATA Gen1 GTX- set RXCDR_CFG=72'h03_8000_8BFF_4010_0008

        --For SATA Gen2 GTX- set RXCDR_CFG=72'h03_8800_8BFF_4020_0008

        --For SATA Gen3 GTX- set RXCDR_CFG=72'h03_8000_8BFF_1020_0010

        --For SATA Gen3 GTP- set RXCDR_CFG=83'h0_0000_87FE_2060_2444_1010

        --For SATA Gen2 GTP- set RXCDR_CFG=83'h0_0000_47FE_2060_2448_1010

        --For SATA Gen1 GTP- set RXCDR_CFG=83'h0_0000_47FE_1060_2448_1010
        RXCDR_CFG               => (x"0000107FE106001041010"),
        RXCDR_FR_RESET_ON_EIDLE => ('0'),
        RXCDR_HOLD_DURING_EIDLE => ('0'),
        RXCDR_PH_RESET_ON_EIDLE => ('0'),
        RXCDR_LOCK_CFG          => ("001001"),

        -------------------RX Initialization and Reset Attributes-------------------
        RXCDRFREQRESET_TIME => ("00001"),
        RXCDRPHRESET_TIME   => ("00001"),
        RXISCANRESET_TIME   => ("00001"),
        RXPCSRESET_TIME     => ("00001"),
        RXPMARESET_TIME     => ("00011"),

        -------------------RX OOB Signaling Attributes-------------------
        RXOOB_CFG => ("0000110"),

        -------------------------RX Gearbox Attributes---------------------------
        RXGEARBOX_EN => ("FALSE"),
        GEARBOX_MODE => ("000"),

        -------------------------PRBS Detection Attribute-----------------------
        RXPRBS_ERR_LOOPBACK => ('0'),

        -------------Power-Down Attributes----------
        PD_TRANS_TIME_FROM_P2 => (x"03c"),
        PD_TRANS_TIME_NONE_P2 => (x"19"),
        PD_TRANS_TIME_TO_P2   => (x"64"),

        -------------RX OOB Signaling Attributes----------
        SAS_MAX_COM        => (64),
        SAS_MIN_COM        => (36),
        SATA_BURST_SEQ_LEN => ("0101"),
        SATA_BURST_VAL     => ("100"),
        SATA_EIDLE_VAL     => ("100"),
        SATA_MAX_BURST     => (8),
        SATA_MAX_INIT      => (21),
        SATA_MAX_WAKE      => (7),
        SATA_MIN_BURST     => (4),
        SATA_MIN_INIT      => (12),
        SATA_MIN_WAKE      => (4),

        -------------RX Fabric Clock Output Control Attributes----------
        TRANS_TIME_RATE => (x"0E"),

        --------------TX Buffer Attributes----------------
        TXBUF_EN                   => ("TRUE"),
        TXBUF_RESET_ON_RATE_CHANGE => ("TRUE"),
        TXDLY_CFG                  => (x"001F"),
        TXDLY_LCFG                 => (x"030"),
        TXDLY_TAP_CFG              => (x"0000"),
        TXPH_CFG                   => (x"0780"),
        TXPHDLY_CFG                => (x"084020"),
        TXPH_MONITOR_SEL           => ("00000"),
        TX_XCLK_SEL                => ("TXOUT"),

        -------------------------FPGA TX Interface Attributes-------------------------
        TX_DATA_WIDTH => data_width_config_c.internal_width,

        -------------------------TX Configurable Driver Attributes-------------------------
        TX_DEEMPH0              => ("000000"),
        TX_DEEMPH1              => ("000000"),
        TX_EIDLE_ASSERT_DELAY   => ("110"),
        TX_EIDLE_DEASSERT_DELAY => ("100"),
        TX_LOOPBACK_DRIVE_HIZ   => ("FALSE"),
        TX_MAINCURSOR_SEL       => ('0'),
        TX_DRIVE_MODE           => ("DIRECT"),
        TX_MARGIN_FULL_0        => ("1001110"),
        TX_MARGIN_FULL_1        => ("1001001"),
        TX_MARGIN_FULL_2        => ("1000101"),
        TX_MARGIN_FULL_3        => ("1000010"),
        TX_MARGIN_FULL_4        => ("1000000"),
        TX_MARGIN_LOW_0         => ("1000110"),
        TX_MARGIN_LOW_1         => ("1000100"),
        TX_MARGIN_LOW_2         => ("1000010"),
        TX_MARGIN_LOW_3         => ("1000000"),
        TX_MARGIN_LOW_4         => ("1000000"),

        -------------------------TX Gearbox Attributes--------------------------
        TXGEARBOX_EN => ("FALSE"),

        -------------------------TX Initialization and Reset Attributes--------------------------
        TXPCSRESET_TIME => ("00001"),
        TXPMARESET_TIME => ("00001"),

        -------------------------TX Receiver Detection Attributes--------------------------
        TX_RXDETECT_CFG => (x"1832"),
        TX_RXDETECT_REF => ("100"),

        ------------------ JTAG Attributes ---------------
        ACJTAG_DEBUG_MODE => ('0'),
        ACJTAG_MODE       => ('0'),
        ACJTAG_RESET      => ('0'),

        ------------------ CDR Attributes ---------------
        CFOK_CFG             => (x"49000040E80"),
        CFOK_CFG2            => ("0100000"),
        CFOK_CFG3            => ("0100000"),
        CFOK_CFG4            => ('0'),
        CFOK_CFG5            => (x"0"),
        CFOK_CFG6            => ("0000"),
        RXOSCALRESET_TIME    => ("00011"),
        RXOSCALRESET_TIMEOUT => ("00000"),

        ------------------ PMA Attributes ---------------
        CLK_COMMON_SWING      => ('0'),
        RX_CLKMUX_EN          => ('1'),
        TX_CLKMUX_EN          => ('1'),
        ES_CLK_PHASE_SEL      => ('0'),
        USE_PCS_CLK_PHASE_SEL => ('0'),
        PMA_RSV6              => ('0'),
        PMA_RSV7              => ('0'),

        ------------------ TX Configuration Driver Attributes ---------------
        TX_PREDRIVER_MODE => ('0'),
        PMA_RSV5          => ('0'),
        SATA_PLL_CFG      => ("VCO_3000MHZ"),

        ------------------ RX Fabric Clock Output Control Attributes ---------------
        RXOUT_DIV => pll_mult_div_config_c.D,

        ------------------ TX Fabric Clock Output Control Attributes ---------------
        TXOUT_DIV => pll_mult_div_config_c.D,

        ------------------ RX Phase Interpolator Attributes---------------
        RXPI_CFG0 => ("000"),
        RXPI_CFG1 => ('1'),
        RXPI_CFG2 => ('1'),

        --------------RX Equalizer Attributes-------------
        ADAPT_CFG0                 => (x"00000"),
        RXLPMRESET_TIME            => ("0001111"),
        RXLPM_BIAS_STARTUP_DISABLE => ('0'),
        RXLPM_CFG                  => ("0110"),
        RXLPM_CFG1                 => ('0'),
        RXLPM_CM_CFG               => ('0'),
        RXLPM_GC_CFG               => ("111100010"),
        RXLPM_GC_CFG2              => ("001"),
        RXLPM_HF_CFG               => ("00001111110000"),
        RXLPM_HF_CFG2              => ("01010"),
        RXLPM_HF_CFG3              => ("0000"),
        RXLPM_HOLD_DURING_EIDLE    => ('0'),
        RXLPM_INCM_CFG             => ('1'),
        RXLPM_IPCM_CFG             => ('0'),
        RXLPM_LF_CFG               => ("000000001111110000"),
        RXLPM_LF_CFG2              => ("01010"),
        RXLPM_OSINT_CFG            => ("100"),

        ------------------ TX Phase Interpolator PPM Controller Attributes---------------
        TXPI_CFG0          => ("00"),
        TXPI_CFG1          => ("00"),
        TXPI_CFG2          => ("00"),
        TXPI_CFG3          => ('0'),
        TXPI_CFG4          => ('0'),
        TXPI_CFG5          => ("000"),
        TXPI_GREY_SEL      => ('0'),
        TXPI_INVSTROBE_SEL => ('0'),
        TXPI_PPMCLK_SEL    => ("TXUSRCLK2"),
        TXPI_PPM_CFG       => (x"00"),
        TXPI_SYNFREQ_PPM   => ("001"),

        ------------------ LOOPBACK Attributes---------------
        LOOPBACK_CFG     => ('0'),
        PMA_LOOPBACK_CFG => ('0'),

        ------------------RX OOB Signalling Attributes---------------
        RXOOB_CLK_CFG => ("PMA"),

        ------------------TX OOB Signalling Attributes---------------
        TXOOB_CFG => ('0'),

        ------------------RX Buffer Attributes---------------
        RXSYNC_MULTILANE => ('0'),
        RXSYNC_OVRD      => ('0'),
        RXSYNC_SKIP_DA   => ('0'),

        ------------------TX Buffer Attributes---------------
        TXSYNC_MULTILANE => ('0'),
        TXSYNC_OVRD      => ('1'),
        TXSYNC_SKIP_DA   => ('0')


        )
      port map
      (
        --------------------------------- CPLL Ports -------------------------------
        GTRSVD                     => "0000000000000000",
        PCSRSVDIN                  => "0000000000000000",
        TSTIN                      => "11111111111111111111",
        ---------------------------- Channel - DRP Ports  --------------------------
        DRPADDR                    => s_drp_addr,
        DRPCLK                     => s_stableclk,
        DRPDI                      => s_drp_data_in,
        DRPDO                      => s_drp_data_out,
        DRPEN                      => s_drp_en,
        DRPRDY                     => s_drp_rdy,
        DRPWE                      => s_drp_wr,
        ------------------------------- Clocking Ports -----------------------------
        RXSYSCLKSEL                => "00",
        TXSYSCLKSEL                => "00",
        ----------------- FPGA TX Interface Datapath Configuration  ----------------
        TX8B10BEN                  => '1',
        ------------------------ GTPE2_CHANNEL Clocking Ports ----------------------
        PLL0CLK                    => s_pll_0_out,
        PLL0REFCLK                 => s_pll_0_outref,
        PLL1CLK                    => '0',
        PLL1REFCLK                 => '0',
        ------------------------------- Loopback Ports -----------------------------
        LOOPBACK                   => loopback_config_c,
        ----------------------------- PCI Express Ports ----------------------------
        PHYSTATUS                  => open,
        RXRATE                     => "000",
        RXVALID                    => open,
        ----------------------------- PMA Reserved Ports ---------------------------
        PMARSVDIN3                 => '0',
        PMARSVDIN4                 => '0',
        ------------------------------ Power-Down Ports ----------------------------
        RXPD                       => "00",
        TXPD                       => "00",
        -------------------------- RX 8B/10B Decoder Ports -------------------------
        SETERRSTATUS               => '0',
        --------------------- RX Initialization and Reset Ports --------------------
        EYESCANRESET               => '0',
        RXUSERRDY                  => s_rx_ready,
        -------------------------- RX Margin Analysis Ports ------------------------
        EYESCANDATAERROR           => open,
        EYESCANMODE                => '0',
        EYESCANTRIGGER             => '0',
        ------------------------------- Receive Ports ------------------------------
        CLKRSVD0                   => '0',
        CLKRSVD1                   => '0',
        DMONFIFORESET              => '0',
        DMONITORCLK                => '0',
        RXPMARESETDONE             => s_pma_rst_done,
        SIGVALIDCLK                => '0',
        ------------------------- Receive Ports - CDR Ports ------------------------
        RXCDRFREQRESET             => '0',
        RXCDRHOLD                  => s_cdr_hold,
        RXCDRLOCK                  => open,
        RXCDROVRDEN                => '0',
        RXCDRRESET                 => '0',
        RXCDRRESETRSV              => '0',
        RXOSCALRESET               => '0',
        RXOSINTCFG                 => "0010",
        RXOSINTDONE                => open,
        RXOSINTHOLD                => '0',
        RXOSINTOVRDEN              => '0',
        RXOSINTPD                  => '0',
        RXOSINTSTARTED             => open,
        RXOSINTSTROBE              => '0',
        RXOSINTSTROBESTARTED       => open,
        RXOSINTTESTOVRDEN          => '0',
        ------------------- Receive Ports - Clock Correction Ports -----------------
        RXCLKCORCNT                => open,
        ---------- Receive Ports - FPGA RX Interface Datapath Configuration --------
        RX8B10BEN                  => '1',
        ------------------ Receive Ports - FPGA RX Interface Ports -----------------
        RXDATA                     => s_gtp_rx_data,
        RXUSRCLK                   => s_txusrclk2_buff,
        RXUSRCLK2                  => s_txusrclk2_buff,
        ------------------- Receive Ports - Pattern Checker Ports ------------------
        RXPRBSERR                  => open,
        RXPRBSSEL                  => "000",
        ------------------- Receive Ports - Pattern Checker ports ------------------
        RXPRBSCNTRESET             => '0',
        ------------------ Receive Ports - RX 8B/10B Decoder Ports -----------------
        RXCHARISCOMMA(3 downto 2)  => s_rxchariscomma(3 downto 2),
        RXCHARISCOMMA(1 downto 0)  => s_rxchariscomma(1 downto 0),
        RXCHARISK(3 downto 2)      => s_rxcharisk(3 downto 2),
        RXCHARISK(1 downto 0)      => s_rxcharisk(1 downto 0),
        RXDISPERR(3 downto 2)      => s_rxdisperr(3 downto 2),
        RXDISPERR(1 downto 0)      => s_rxdisperr(1 downto 0),
        RXNOTINTABLE(3 downto 2)   => s_rxcodeerr(3 downto 2),
        RXNOTINTABLE(1 downto 0)   => s_rxcodeerr(1 downto 0),
        ------------------------ Receive Ports - RX AFE Ports ----------------------
        GTPRXN                     => lane_rx_i(lane_idx).n,
        GTPRXP                     => lane_rx_i(lane_idx).p,
        PMARSVDIN2                 => '0',
        PMARSVDOUT0                => open,
        PMARSVDOUT1                => open,
        ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
        RXBUFRESET                 => '0',
        RXBUFSTATUS                => open,
        RXDDIEN                    => '0',
        RXDLYBYPASS                => '1',
        RXDLYEN                    => '0',
        RXDLYOVRDEN                => '0',
        RXDLYSRESET                => '0',
        RXDLYSRESETDONE            => open,
        RXPHALIGN                  => '0',
        RXPHALIGNDONE              => open,
        RXPHALIGNEN                => '0',
        RXPHDLYPD                  => '0',
        RXPHDLYRESET               => '0',
        RXPHMONITOR                => open,
        RXPHOVRDEN                 => '0',
        RXPHSLIPMONITOR            => open,
        RXSTATUS                   => open,
        RXSYNCALLIN                => '0',
        RXSYNCDONE                 => open,
        RXSYNCIN                   => '0',
        RXSYNCMODE                 => '0',
        RXSYNCOUT                  => open,
        -------------- Receive Ports - RX Byte and Word Alignment Ports ------------
        RXBYTEISALIGNED            => open,
        RXBYTEREALIGN              => open,
        RXCOMMADET                 => open,
        RXCOMMADETEN               => '1',
        RXMCOMMAALIGNEN            => s_mcomma_align_en,
        RXPCOMMAALIGNEN            => s_pcomma_align_en,
        RXSLIDE                    => '0',
        ------------------ Receive Ports - RX Channel Bonding Ports ----------------
        RXCHANBONDSEQ              => open,
        RXCHBONDEN                 => '0',
        RXCHBONDI                  => "0000",
        RXCHBONDLEVEL              => "000",
        RXCHBONDMASTER             => '0',
        RXCHBONDO                  => open,
        RXCHBONDSLAVE              => '0',
        ----------------- Receive Ports - RX Channel Bonding Ports  ----------------
        RXCHANISALIGNED            => open,
        RXCHANREALIGN              => open,
        ------------ Receive Ports - RX Decision Feedback Equalizer(DFE) -----------
        DMONITOROUT                => open,
        RXADAPTSELTEST             => "00000000000000",
        RXDFEXYDEN                 => '0',
        RXOSINTEN                  => '1',
        RXOSINTID0                 => "0000",
        RXOSINTNTRLEN              => '0',
        RXOSINTSTROBEDONE          => open,
        ------- Receive Ports - RX Driver,OOB signalling,Coupling and Eq.,CDR ------
        RXLPMLFOVRDEN              => '0',
        RXLPMOSINTNTRLEN           => '0',
        -------------------- Receive Ports - RX Equailizer Ports -------------------
        RXLPMHFHOLD                => '0',
        RXLPMHFOVRDEN              => '0',
        RXLPMLFHOLD                => '0',
        --------------------- Receive Ports - RX Equalizer Ports -------------------
        RXOSHOLD                   => '0',
        RXOSOVRDEN                 => '0',
        ------------ Receive Ports - RX Fabric ClocK Output Control Ports ----------
        RXRATEDONE                 => open,
        ----------- Receive Ports - RX Fabric Clock Output Control Ports  ----------
        RXRATEMODE                 => '0',
        --------------- Receive Ports - RX Fabric Output Control Ports -------------
        RXOUTCLK                   => open,
        RXOUTCLKFABRIC             => open,
        RXOUTCLKPCS                => open,
        RXOUTCLKSEL                => "010",
        ---------------------- Receive Ports - RX Gearbox Ports --------------------
        RXDATAVALID                => open,
        RXHEADER                   => open,
        RXHEADERVALID              => open,
        RXSTARTOFSEQ               => open,
        --------------------- Receive Ports - RX Gearbox Ports  --------------------
        RXGEARBOXSLIP              => '0',
        ------------- Receive Ports - RX Initialization and Reset Ports ------------
        GTRXRESET                  => s_gtp_rst,
        RXLPMRESET                 => '0',
        RXOOBRESET                 => '0',
        RXPCSRESET                 => '0',
        RXPMARESET                 => '0',
        ------------------- Receive Ports - RX OOB Signaling ports -----------------
        RXCOMSASDET                => open,
        RXCOMWAKEDET               => open,
        ------------------ Receive Ports - RX OOB Signaling ports  -----------------
        RXCOMINITDET               => open,
        ------------------ Receive Ports - RX OOB signalling Ports -----------------
        RXELECIDLE                 => open,
        RXELECIDLEMODE             => "11",
        ----------------- Receive Ports - RX Polarity Control Ports ----------------
        RXPOLARITY                 => '0',
        -------------- Receive Ports -RX Initialization and Reset Ports ------------
        RXRESETDONE                => open,
        --------------------------- TX Buffer Bypass Ports -------------------------
        TXPHDLYTSTCLK              => '0',
        ------------------------ TX Configurable Driver Ports ----------------------
        TXPOSTCURSOR               => "00000",
        TXPOSTCURSORINV            => '0',
        TXPRECURSOR                => "00000",
        TXPRECURSORINV             => '0',
        -------------------- TX Fabric Clock Output Control Ports ------------------
        TXRATEMODE                 => '0',
        --------------------- TX Initialization and Reset Ports --------------------
        CFGRESET                   => '0',
        GTTXRESET                  => s_gtp_rst,
        PCSRSVDOUT                 => open,
        TXUSERRDY                  => s_tx_ready,
        ----------------- TX Phase Interpolator PPM Controller Ports ---------------
        TXPIPPMEN                  => '0',
        TXPIPPMOVRDEN              => '0',
        TXPIPPMPD                  => '0',
        TXPIPPMSEL                 => '1',
        TXPIPPMSTEPSIZE            => "00000",
        ---------------------- Transceiver Reset Mode Operation --------------------
        GTRESETSEL                 => '0',    -- Sequential mode
        RESETOVRD                  => '0',
        ------------------------------- Transmit Ports -----------------------------
        TXPMARESETDONE             => open,
        ----------------- Transmit Ports - Configurable Driver Ports ---------------
        PMARSVDIN0                 => '0',
        PMARSVDIN1                 => '0',
        ------------------ Transmit Ports - FPGA TX Interface Ports ----------------
        TXDATA                     => s_gtp_tx_data,
        TXUSRCLK                   => s_txusrclk2_buff,
        TXUSRCLK2                  => s_txusrclk2_buff,
        --------------------- Transmit Ports - PCI Express Ports -------------------
        TXELECIDLE                 => '0',
        TXMARGIN                   => "000",
        TXRATE                     => "000",
        TXSWING                    => '0',
        ------------------ Transmit Ports - Pattern Generator Ports ----------------
        TXPRBSFORCEERR             => '0',
        ------------------ Transmit Ports - TX 8B/10B Encoder Ports ----------------
        TX8B10BBYPASS              => "0000",
        TXCHARDISPMODE(3 downto 2) => "00",
        TXCHARDISPMODE(1 downto 0) => "00",
        TXCHARDISPVAL(3 downto 2)  => "00",
        TXCHARDISPVAL(1 downto 0)  => "00",
        TXCHARISK(3 downto 2)      => s_txcharisk(3 downto 2),
        TXCHARISK(1 downto 0)      => s_txcharisk(1 downto 0),
        ------------------ Transmit Ports - TX Buffer Bypass Ports -----------------
        TXDLYBYPASS                => '1',
        TXDLYEN                    => '0',
        TXDLYHOLD                  => '0',
        TXDLYOVRDEN                => '0',
        TXDLYSRESET                => '0',
        TXDLYSRESETDONE            => open,
        TXDLYUPDOWN                => '0',
        TXPHALIGN                  => '0',
        TXPHALIGNDONE              => open,
        TXPHALIGNEN                => '0',
        TXPHDLYPD                  => '0',
        TXPHDLYRESET               => '0',
        TXPHINIT                   => '0',
        TXPHINITDONE               => open,
        TXPHOVRDEN                 => '0',
        ---------------------- Transmit Ports - TX Buffer Ports --------------------
        TXBUFSTATUS                => open,
        ------------ Transmit Ports - TX Buffer and Phase Alignment Ports ----------
        TXSYNCALLIN                => '0',
        TXSYNCDONE                 => open,
        TXSYNCIN                   => '0',
        TXSYNCMODE                 => '0',
        TXSYNCOUT                  => open,
        --------------- Transmit Ports - TX Configurable Driver Ports --------------
        GTPTXN                     => lane_tx_o(lane_idx).n,
        GTPTXP                     => lane_tx_o(lane_idx).p,
        TXBUFDIFFCTRL              => "100",
        TXDEEMPH                   => '0',
        TXDIFFCTRL                 => "1001",
        TXDIFFPD                   => '0',
        TXINHIBIT                  => '0',
        TXMAINCURSOR               => "0000000",
        TXPISOPD                   => '0',
        ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
        TXOUTCLK                   => s_tx_out_clock,
        TXOUTCLKFABRIC             => open,
        TXOUTCLKPCS                => open,
        TXOUTCLKSEL                => "010",
        TXRATEDONE                 => open,
        --------------------- Transmit Ports - TX Gearbox Ports --------------------
        TXGEARBOXREADY             => open,
        TXHEADER                   => "000",
        TXSEQUENCE                 => "0000000",
        TXSTARTSEQ                 => '0',
        ------------- Transmit Ports - TX Initialization and Reset Ports -----------
        TXPCSRESET                 => '0',
        TXPMARESET                 => '0',
        TXRESETDONE                => open,
        ------------------ Transmit Ports - TX OOB signalling Ports ----------------
        TXCOMFINISH                => open,
        TXCOMINIT                  => '0',
        TXCOMSAS                   => '0',
        TXCOMWAKE                  => '0',
        TXPDELECIDLEMODE           => '0',
        ----------------- Transmit Ports - TX Polarity Control Ports ---------------
        TXPOLARITY                 => '0',
        --------------- Transmit Ports - TX Receiver Detection Ports  --------------
        TXDETECTRX                 => '0',
        ------------------ Transmit Ports - pattern Generator Ports ----------------
        TXPRBSSEL                  => "000"

        );

  end generate;

  -- FIXME: do something with the APB input bus, maybe nothing for now

end architecture;
