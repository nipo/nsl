library ieee;
use ieee.std_logic_1164.all;

library work, nsl_line_coding, nsl_io, nsl_logic, nsl_bnoc;
use nsl_logic.bool.all;
use nsl_line_coding.ibm_8b10b.all;
use nsl_io.diff.all;
use nsl_io.pad.all;
use nsl_io.serdes.all;
use work.link.all;
use work.flit.all;
use work.sgmii.all;

entity sgmii_driver is
  
  port (
    reset_n_i  : in std_ulogic;
    clock125_i : in std_ulogic;
    clock625_i : in std_ulogic;

    sgmii_o : out sgmii_m2p;
    sgmii_i : in  sgmii_p2m;

    link_speed_i : in link_speed_t := LINK_SPEED_1000;

    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in  nsl_bnoc.committed.committed_ack;

    tx_i : in  nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );    

end entity sgmii_driver;

architecture beh of sgmii_driver is

  -- Internal signals
  signal s_clk_m2p_diff  : nsl_io.diff.diff_pair;
  signal s_clk_p2m_diff  : nsl_io.diff.diff_pair;
  signal s_data_m2p_diff : nsl_io.diff.diff_pair;
  signal s_data_p2m_diff : nsl_io.diff.diff_pair;

  signal s_clk_m2p_se  : std_ulogic;
  signal s_clk_p2m_se  : std_ulogic;
  signal s_data_m2p_se : std_ulogic;
  signal s_data_p2m_se : std_ulogic;

  signal s_rx_config_valid : std_ulogic;
  signal s_rx_config       : config_reg_t;
  signal s_rx_idle_match   : std_ulogic;
  signal s_tx_send_config  : std_ulogic;
  signal s_tx_config       : config_reg_t;
  signal s_link_up         : std_ulogic;

  signal s_tx2enc_symbol : nsl_line_coding.ibm_8b10b.data_t;
  signal s_dec2rx_symbol : nsl_line_coding.ibm_8b10b.data_t;
  signal s_ser2dec_code  : nsl_line_coding.ibm_8b10b.code_word_t;
  signal s_enc2ser_code  : nsl_line_coding.ibm_8b10b.code_word_t;

  signal s_tx_flit           : mii_flit_t;
  signal s_rx_flit           : mii_flit_t;
  signal s_rx_flit_valid     : std_ulogic;
  signal s_rx_valid_2_commit : std_ulogic;

  signal s_bitslip         : std_ulogic;
  signal s_mark_serdes_in  : std_ulogic;
  signal s_autoneg_restart : std_ulogic;

  signal s_dec_valid_o       : std_ulogic;
  signal s_code_error_o      : std_ulogic;
  signal s_disparity_error_o : std_ulogic;
  signal s_enc_valid_o       : std_ulogic;

  signal s_bit_rstn_cheat : std_ulogic;

begin  -- architecture beh

  -- Signal assignments
  -- Differential pairs
  sgmii_o.clk_m2p_diff  <= s_clk_m2p_diff;
  sgmii_o.data_m2p_diff <= s_data_m2p_diff;
  s_clk_p2m_diff        <= sgmii_i.clk_p2m_diff;
  s_data_p2m_diff       <= sgmii_i.data_p2m_diff;

  -- Component instatiation
  -- RX side
  sgmii_pcs_rx_1 : work.sgmii.sgmii_pcs_rx
    port map (
      clock_i        => clock125_i,
      reset_n_i      => reset_n_i,
      symbol_i       => s_dec2rx_symbol,
      flit_o         => s_rx_flit,
      config_valid_o => s_rx_config_valid,
      config_o       => s_rx_config,
      valid_o        => s_rx_valid_2_commit,
      idle_match_o   => s_rx_idle_match
      );

  rx_to_committed : work.flit.mii_flit_to_committed
    port map(
      clock_i   => clock125_i,
      reset_n_i => reset_n_i,

      flit_i  => s_rx_flit,
      valid_i => s_rx_valid_2_commit,

      committed_o => rx_o,
      committed_i => rx_i
      );

  ibm_8b10b_decoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map (
      implementation_c => "logic")
    port map (
      clock_i           => clock125_i,
      reset_n_i         => reset_n_i,
      valid_i           => '1',
      data_i            => s_ser2dec_code,
      valid_o           => s_dec_valid_o,
      data_o            => s_dec2rx_symbol,
      code_error_o      => s_code_error_o,
      disparity_error_o => s_disparity_error_o  -- FIXME: hook this up to the
                                                -- synchronizer
      );

  -- Cheat with the bitslip for now
  bitslip_cheater : process (s_data_p2m_se) is
  begin  -- process bitslip_cheater
    if s_data_p2m_se = 'U' then
      s_bit_rstn_cheat <= '0';
    else
      s_bit_rstn_cheat <= '1';
    end if;
  end process bitslip_cheater;

  serdes_ddr10_input_1 : nsl_io.serdes.serdes_ddr10_input
    generic map (
      left_to_right_c => false)
    port map (
      bit_clock_i  => clock625_i,
      word_clock_i => clock125_i,       --FIXME: use different clock source when
                                        --you have the synchronizer
      reset_n_i    => s_bit_rstn_cheat,
      serial_i     => s_data_p2m_se,
      parallel_o   => s_ser2dec_code,
      bitslip_i    => '0',              -- FIXME: need synchronizer to pilot this to
                                        -- synchronize incoming data
      mark_o       => s_mark_serdes_in  -- FIXME: same as above
      );

  pad_diff_input_1 : nsl_io.pad.pad_diff_input
    generic map (
      diff_term => true,
      is_clock  => false,
      invert    => false)
    port map (
      p_diff => s_data_p2m_diff,
      p_se   => s_data_p2m_se
      );

  pad_diff_input_2 : nsl_io.pad.pad_diff_input
    generic map (
      diff_term => true,
      is_clock  => true,
      invert    => false)
    port map (
      p_diff => s_clk_p2m_diff,
      p_se   => s_clk_p2m_se
      );

  -- TX side

  s_clk_m2p_se <= clock125_i;

  sgmii_pcs_tx_1 : work.sgmii.sgmii_pcs_tx
    port map (
      clock_i       => clock125_i,
      reset_n_i     => reset_n_i,
      flit_i        => s_tx_flit,
      symbol_o      => s_tx2enc_symbol,
      send_config_i => s_tx_send_config,
      config_i      => s_tx_config,
      link_up_i     => s_link_up
      );

  tx_from_committed : work.flit.mii_flit_from_committed
    generic map(
      ipg_c => 96
      )
    port map(
      clock_i   => clock125_i,
      reset_n_i => reset_n_i,

      committed_i => tx_i,
      committed_o => tx_o,

      flit_o  => s_tx_flit,
      ready_i => s_link_up
      );

  ibm_8b10b_encoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map (
      implementation_c => "logic")
    port map (
      clock_i   => clock125_i,
      reset_n_i => reset_n_i,
      valid_i   => '1',
      data_i    => s_tx2enc_symbol,
      valid_o   => s_enc_valid_o,
      data_o    => s_enc2ser_code
      );

  serdes_ddr10_output_1 : nsl_io.serdes.serdes_ddr10_output
    generic map (
      left_to_right_c => false)
    port map (
      bit_clock_i  => clock625_i,
      word_clock_i => s_clk_m2p_se,
      reset_n_i    => reset_n_i,
      parallel_i   => s_enc2ser_code,
      serial_o     => s_data_m2p_se
      );

  pad_diff_output_1 : nsl_io.pad.pad_diff_output
    generic map (
      is_clock => false)
    port map (
      p_se   => s_data_m2p_se,
      p_diff => s_data_m2p_diff
      );

  pad_diff_output_2 : nsl_io.pad.pad_diff_output
    generic map (
      is_clock => true)
    port map (
      p_se   => s_clk_m2p_se,
      p_diff => s_clk_m2p_diff
      );

  -- Auto negotiation
  sgmii_autoneg_1 : work.sgmii.sgmii_autoneg
    generic map (
      link_timer_cycles_c => 30)                -- FIXME: not sure how many timer cycles
                                                -- we want
    port map (
      clock_i           => clock125_i,
      reset_n_i         => reset_n_i,
      config_i          => "0000000000100000",  -- See IEEE 802.3 clause 37
                                                -- Full Duplex only, no pause,
                                                -- no next page
                                                -- 0------0001----- (put zeros in place
                                                -- of don't cares
      restart_i         => s_autoneg_restart,   -- FIXME: use this to restart if
                                                -- connection is lost (the synchronizer
                                                -- can tell you this)
      rx_config_valid_i => s_rx_config_valid,
      rx_config_i       => s_rx_config,
      rx_idle_i         => s_rx_idle_match,
      send_config_o     => s_tx_send_config,
      tx_config_o       => s_tx_config,
      link_up_o         => s_link_up
      -- partner_config_o  => partner_config_o -- FIXME: not sure I need this
      );  

end architecture beh;
