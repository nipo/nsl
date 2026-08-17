library ieee;
use ieee.std_logic_1164.all;

library work, nsl_bnoc;
use work.link.all;
use work.flit.all;
use work.sgmii.all;

entity sgmii_driver is
  generic (
    link_timer_c : positive := 200000
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    sgmii_o : out sgmii_m2p;
    sgmii_i : in  sgmii_p2m;

    link_speed_i : in  link_speed_t := LINK_SPEED_1000;
    link_up_o    : out std_ulogic;

    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in  nsl_bnoc.committed.committed_ack;

    tx_i : in  nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );

end entity sgmii_driver;

architecture beh of sgmii_driver is

  -- Internal signals
  signal s_rx_config_valid : std_ulogic;
  signal s_rx_config       : config_reg_t;
  signal s_rx_idle_match   : std_ulogic;
  signal s_tx_send_config  : std_ulogic;
  signal s_tx_config       : config_reg_t;
  signal s_link_up         : std_ulogic;

  signal s_tx_flit           : mii_flit_t;
  signal s_rx_flit           : mii_flit_t;
  signal s_rx_valid_2_commit : std_ulogic;

  signal s_autoneg_restart : std_ulogic;

  signal s_symbol_expected : std_ulogic;
  signal s_valid_symbol    : std_ulogic;

  signal s_align_rst   : std_ulogic;

  signal s_loss_connect_rst_n : std_ulogic;

begin  -- architecture beh

  -- Signal assignments
  -- Outputs
  sgmii_o.align_rst    <= s_align_rst;
  sgmii_o.sys_reset_n  <= s_loss_connect_rst_n;
  sgmii_o.valid_symbol <= s_valid_symbol;

  -- Valid symbol
  s_valid_symbol <= s_symbol_expected and not(sgmii_i.code_err) and not(sgmii_i.disparity_err);

  -- Link up
  link_up_o <= s_link_up;

  -- Restart autonegotiation on loss of connection -----------------------------------------
  s_autoneg_restart <= not(sgmii_i.align_ready);

  sys_rst : process (clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      s_loss_connect_rst_n <= '0';
    elsif rising_edge(clock_i) then     -- rising clock edge
      if (s_link_up = '1') and (s_valid_symbol = '0') then
        s_loss_connect_rst_n <= '0';
      else
        s_loss_connect_rst_n <= reset_n_i;
      end if;
    end if;
  end process;

  align_rst : process (clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      s_align_rst <= '1';
    elsif rising_edge(clock_i) then     -- rising clock edge
      if (sgmii_i.align_ready = '1') and (s_valid_symbol = '0') then
        s_align_rst <= '1';
      else
        s_align_rst <= not(reset_n_i);
      end if;
    end if;
  end process;

  -- Component instatiation
  -- RX side --------------------------------------------------------------------------------
  sgmii_pcs_rx_1 : work.sgmii.sgmii_pcs_rx
    port map (
      clock_i           => clock_i,
      reset_n_i         => s_loss_connect_rst_n,
      symbol_i          => sgmii_i.data_p2m_symbol,
      symbol_expected_o => s_symbol_expected,
      flit_o            => s_rx_flit,
      config_valid_o    => s_rx_config_valid,
      config_o          => s_rx_config,
      valid_o           => s_rx_valid_2_commit,
      idle_match_o      => s_rx_idle_match
      );

  rx_to_committed : work.flit.mii_flit_to_committed
    port map(
      clock_i   => clock_i,
      reset_n_i => s_loss_connect_rst_n,

      flit_i  => s_rx_flit,
      valid_i => s_rx_valid_2_commit,

      committed_o => rx_o,
      committed_i => rx_i
      );

  -- TX side --------------------------------------------------------------------------------

  sgmii_pcs_tx_1 : work.sgmii.sgmii_pcs_tx
    port map (
      clock_i       => clock_i,
      reset_n_i     => s_loss_connect_rst_n,
      flit_i        => s_tx_flit,
      symbol_o      => sgmii_o.data_m2p_symbol,
      send_config_i => s_tx_send_config,
      config_i      => s_tx_config,
      link_up_i     => s_link_up
      );

  tx_from_committed : work.flit.mii_flit_from_committed
    generic map(
      ipg_c => 96
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => s_loss_connect_rst_n,

      committed_i => tx_i,
      committed_o => tx_o,

      flit_o  => s_tx_flit,
      ready_i => s_link_up
      );

  -- Auto negotiation ----------------------------------------------------------------------
  sgmii_autoneg_1 : work.sgmii.sgmii_autoneg
    generic map (
      link_timer_cycles_c => link_timer_c)
    port map (
      clock_i           => clock_i,
      reset_n_i         => s_loss_connect_rst_n,
      config_i          => "0000000000100000",  -- See IEEE 802.3 clause 37
                                                -- Full Duplex only, no pause,
                                                -- no next page
                                                -- 0------0001----- (put zeros in place
                                                -- of don't cares)
      restart_i         => s_autoneg_restart,
      rx_config_valid_i => s_rx_config_valid,
      rx_config_i       => s_rx_config,
      rx_idle_i         => s_rx_idle_match,
      send_config_o     => s_tx_send_config,
      tx_config_o       => s_tx_config,
      link_up_o         => s_link_up
      );

end architecture beh;
