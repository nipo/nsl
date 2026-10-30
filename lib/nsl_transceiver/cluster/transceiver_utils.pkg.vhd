library ieee;
use ieee.std_logic_1164.all;

-- Building blocks shared by the vendor transceiver_cluster
-- architectures.
package transceiver_utils is

  -- Word alignment supervisor, see lane_aligner.vhd
  component lane_aligner is
    generic(
      bypass_c              : boolean := false;
      stabilization_count_c : natural := 300;
      flush_count_c         : natural := 64;
      lost_count_c          : natural := 2**16
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      valid_i   : in std_ulogic;
      restart_i : in std_ulogic;

      align_en_o : out std_ulogic;
      ready_o    : out std_ulogic
      );
  end component;

  -- Adapter <-> transceiver fabric width adaptation, see lane_gearbox.vhd
  component lane_gearbox is
    generic(
      data_byte_count_c : natural;
      interface_width_c : natural
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      tx_data_i     : in std_ulogic_vector(data_byte_count_c * 8 - 1 downto 0);
      tx_charisk_i  : in std_ulogic_vector(data_byte_count_c - 1 downto 0);
      tx_disp_frc_i : in std_ulogic_vector(data_byte_count_c - 1 downto 0);
      tx_disp_val_i : in std_ulogic_vector(data_byte_count_c - 1 downto 0);

      rx_data_o    : out std_ulogic_vector(data_byte_count_c * 8 - 1 downto 0);
      rx_charisk_o : out std_ulogic_vector(data_byte_count_c - 1 downto 0);
      rx_disperr_o : out std_ulogic_vector(data_byte_count_c - 1 downto 0);
      rx_codeerr_o : out std_ulogic_vector(data_byte_count_c - 1 downto 0);

      gt_tx_data_o     : out std_ulogic_vector(interface_width_c - 1 downto 0);
      gt_tx_charisk_o  : out std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
      gt_tx_disp_frc_o : out std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
      gt_tx_disp_val_o : out std_ulogic_vector(interface_width_c / 8 - 1 downto 0);

      gt_rx_data_i    : in std_ulogic_vector(interface_width_c - 1 downto 0);
      gt_rx_charisk_i : in std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
      gt_rx_disperr_i : in std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
      gt_rx_codeerr_i : in std_ulogic_vector(interface_width_c / 8 - 1 downto 0)
      );
  end component;

  -- Reset sequencer for one direction of a GTHE4 channel, see
  -- gthe4_reset_fsm.vhd
  component gthe4_reset_fsm is
    generic(
      timeout_delay_c           : natural;
      gt_pwr_delay_c            : natural
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      power_good_i     : in std_ulogic;
      pll_locked_i     : in std_ulogic;
      pll_reset_done_i : in std_ulogic;
      pma_rst_done_i   : in std_ulogic;
      rst_done_i       : in std_ulogic;

      gth_rst_o : out std_ulogic;
      ready_o   : out std_ulogic
      );
  end component;

  -- Reset sequencer for a GTPE2 channel (PLL wait + DRP read-modify-write
  -- around the PMA reset), see gtpe2_reset_fsm.vhd
  component gtpe2_reset_fsm is
    generic(
      timeout_delay_c : natural
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      pll_locked_i     : in std_ulogic;
      pll_reset_done_i : in std_ulogic;
      pma_rst_done_i   : in std_ulogic;

      gtp_rst_o : out std_ulogic;

      drp_addr_o  : out std_ulogic_vector(8 downto 0);
      drp_en_o    : out std_ulogic;
      drp_wr_o    : out std_ulogic;
      drp_wdata_o : out std_ulogic_vector(15 downto 0);
      drp_rdata_i : in  std_ulogic_vector(15 downto 0);
      drp_rdy_i   : in  std_ulogic
      );
  end component;

  -- Reset sequencer for the shared PLLs of a GTPE2 common block, see
  -- gtpe2_pll_reset_fsm.vhd
  component gtpe2_pll_reset_fsm is
    generic(
      delay500ns_c    : natural;
      delay_pll_rst_c : natural := 5
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      pll_pd_o  : out std_ulogic;
      pll_rst_o : out std_ulogic;
      done_o    : out std_ulogic
      );
  end component;

  -- Reset sequencer for the CPLL of a GTHE4 channel, see
  -- gthe4_cpll_reset_fsm.vhd
  component gthe4_cpll_reset_fsm is
    generic(
      hold_delay_c : natural
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      power_good_i : in std_ulogic;

      pll_pd_o : out std_ulogic;
      done_o   : out std_ulogic
      );
  end component;

end package transceiver_utils;
