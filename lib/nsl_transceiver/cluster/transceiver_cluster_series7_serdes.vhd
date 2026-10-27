library ieee;
use ieee.std_logic_1164.all;

-- Series-7 "bulk IO" SERDES implementation of the portable
-- transceiver_cluster contract (see cluster_pkg.vhd).
--
-- Datapath is: ISERDESE2/OSERDESE2 based DDR 10:1 SERDES
-- (nsl_io.serdes), input_delay_variable based bit aligner, and fabric 8b/10b codec.
--
-- Hardware bypassed by the selected loopback mode is not instantiated.
--
-- Loopback (lane.config_t.loopback, static per lane). "PCS" is the 8b/10b
-- codec plus the symbol interface, "PMA" is the SERDES + pads.
--   LOOPBACK_NONE         normal operation
--   LOOPBACK_NEAR_END_PCS user TX symbol is registered and returned as the
--                         user RX symbol (looped before the encoder). The
--                         decoder, SERDES and RX pad are bypassed, the TX pad
--                         keeps transmitting. Errors are 0, align ready is 1.
--   LOOPBACK_NEAR_END_PMA the 10b code word leaving the encoder is fed to
--                         the decoder, bypassing SERDES, input_delay_variable and pads
--                         (the 8b/10b logic is tested, not the IO). The TX
--                         pad keeps transmitting. Align ready is 1.
--   LOOPBACK_FAR_END_PMA  the RX pad net drives the TX pad directly in
--                         fabric, polarity-corrected so the partner gets its
--                         own data back. The RX path keeps working normally
--                         (aligner included), user TX is ignored.
--   LOOPBACK_FAR_END_PCS  the decoded RX symbol feeds the encoder instead
--                         of the user TX symbol. The RX path keeps working
--                         normally, user TX is ignored. There is no rate
--                         matching: the RX word clock is the local clock, not
--                         the partner's.

library nsl_transceiver, nsl_io, nsl_amba, nsl_line_coding, nsl_clocking, nsl_synthesis, nsl_math;
use nsl_math.int_ext.all;
use nsl_amba.apb.all;
use nsl_clocking.pll.all;
use nsl_clocking.pll_backend.all;
use nsl_transceiver.lane.all;
use nsl_transceiver.target.all;

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

    apb_clock_o   : out std_ulogic;
    apb_reset_n_i : in  std_ulogic;
    apb_m_i       : in  nsl_amba.apb.master_t;
    apb_s_o       : out nsl_amba.apb.slave_t
    );
end entity;

architecture series7_serdes of transceiver_cluster is

  -- Constants ---------------------------------------------------------------------------
  constant ref_index_c : natural := 0;

  -- Error messages
  constant lane_count_msg_c    : string := "transceiver_cluster/series7_serdes: at least one lane is required";
  constant ref_clk_msg_c       : string := "transceiver_cluster/series7_serdes: a reference clock is required";
  constant cluster_valid_msg_c : string := "transceiver_cluster/series7_serdes: configuration failed target-agnostic consistency check";
  constant encoding_msg_c      : string := "transceiver_cluster/series7_serdes: lane encoding must be ENCODING_8B10B";
  constant byte_count_msg_c    : string := "transceiver_cluster/series7_serdes: lane data_byte_count must be 1";

  constant ref_clk_ok_c : boolean := ref_index_c < ref_clock_c'length;

  -- True when at least one enabled lane instantiates an RX SERDES path
  -- (input_delay_variable + ISERDES), i.e. when an delay_reference is needed.
  function uses_idelay(cfg : nsl_transceiver.cluster.config_t) return boolean is
  begin
    for i in 0 to cfg.lane_count-1 loop
      if cfg.lanes(i).enabled
        and cfg.lanes(i).loopback /= nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS
        and cfg.lanes(i).loopback /= nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA then
        return true;
      end if;
    end loop;
    return false;
  end function;

  constant idelay_used_c : boolean := uses_idelay(config_c);

  -- APB bus
  constant apb_config_c : nsl_amba.apb.config_t := nsl_amba.apb.config(8, 8);

  -- Clocking
  constant ref_hz_c          : positive := config_c.refclks(0).ref_clock_mhz * 1_000_000;
  constant delay_clock_hz_c  : positive := 200_000_000;
  constant serial_clock_hz_c : positive := positive(real(config_c.lanes(0).line_rate_mbps) / 2.0) * 1_000_000;

  signal s_ref_clk               : std_ulogic;
  signal s_delay_clock           : std_ulogic;
  signal s_serial_clock          : std_ulogic;
  signal s_serial_clock_buff     : std_ulogic;
  signal s_parallel_clock_buff   : std_ulogic;
  signal s_domain_a_pll_reset    : std_ulogic;
  signal s_domain_a_pll_locked   : std_ulogic;
  signal s_domain_a_pll_feedback : std_ulogic;
  signal s_delay_rdy             : std_ulogic;
  signal s_bufr_rst              : std_ulogic;
  signal s_everything_ready      : std_ulogic;
  signal s_general_reset_sync_n  : std_ulogic;

begin

  -- Cluster-level checks ----------------------------------------------------------------
  assert config_c.lane_count >= 1
    report lane_count_msg_c severity failure;

  lane_count_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => lane_count_msg_c,
      condition_c => config_c.lane_count >= 1
      )
    port map(
      unused_i => '0'
      );

  assert ref_clk_ok_c
    report ref_clk_msg_c severity failure;

  ref_clk_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => ref_clk_msg_c,
      condition_c => ref_clk_ok_c
      )
    port map(
      unused_i => '0'
      );

  assert nsl_transceiver.cluster.is_valid(config_c)
    report cluster_valid_msg_c severity failure;

  cluster_valid_check : nsl_synthesis.assertion.synth_assert
    generic map(
      message_c   => cluster_valid_msg_c,
      condition_c => nsl_transceiver.cluster.is_valid(config_c)
      )
    port map(
      unused_i => '0'
      );

  -- APB: no runtime configuration exists for this backend. 
  apb_clock_o <= '0';
  apb_s_o     <= response_idle(apb_config_c);

  -- Common Clocking between lanes: MMCM, BUFIO, BUFR, delay_reference ---------------------------------------
  s_ref_clk <= ref_clock_i(ref_index_c) when ref_index_c < ref_clock_c'length else '0';

  domain_a_pll_inst : nsl_clocking.pll.pll_multi
    generic map (
      config_c         => pll_config(
        implementation => pll_implementation_id("MMCM"),  -- Required for BUFR
        input_hz       => ref_hz_c,
        o0             => pll_output(delay_clock_hz_c, 0, true),
        o1             => pll_output(serial_clock_hz_c)
        )
      )
    port map (
      clock_i    => s_ref_clk,
      clock_o(0) => s_delay_clock,
      clock_o(1) => s_serial_clock,
      reset_n_i  => reset_n_i,
      locked_o   => s_domain_a_pll_locked
      );  

  s_everything_ready <= s_delay_rdy and s_domain_a_pll_locked;

  general_reset_sync : nsl_clocking.async.async_edge
    port map(
      clock_i => s_parallel_clock_buff,
      data_i  => s_everything_ready,
      data_o  => s_general_reset_sync_n
      );

  BUFIO_inst : bufio
    port map (
      O => s_serial_clock_buff,
      I => s_serial_clock
      );

  s_bufr_rst <= not(s_domain_a_pll_locked);

  BUFR_inst : bufr
    generic map (
      BUFR_DIVIDE => "5",
      SIM_DEVICE  => "7SERIES"
      )
    port map (
      O   => s_parallel_clock_buff,
      CE  => s_domain_a_pll_locked,
      CLR => s_bufr_rst,
      I   => s_serial_clock
      );

  -- delay_reference is only needed (and only kept by the tools) when a lane
  -- instantiates an input_delay_variable.
  idelayctrl_gen : if idelay_used_c generate
    signal s_delay_reset_n : std_ulogic;
  begin

    delay_reset_sync : nsl_clocking.async.async_edge
      port map(
        clock_i => s_delay_clock,
        data_i  => s_domain_a_pll_locked,
        data_o  => s_delay_reset_n
        );

    delay_ref_inst : nsl_io.delay.delay_reference
      port map (
        clock_i   => s_delay_clock,
        reset_n_i => s_delay_reset_n,
        ready_o   => s_delay_rdy
        );

  end generate;

  no_idelayctrl_gen : if not idelay_used_c generate
  begin
    s_delay_rdy <= '1';
  end generate;

  -- Lanes ----------------------------------------------------------------------------------
  lanes_gen : for lane_idx in 0 to config_c.lane_count-1 generate

    lane_enabled : if config_c.lanes(lane_idx).enabled generate

      -- Lane constants and signals
      constant lane_c : nsl_transceiver.lane.config_t := config_c.lanes(lane_idx);

      constant encoding_ok_c : boolean                              := lane_c.encoding = nsl_transceiver.lane.ENCODING_8B10B;
      constant bytes_ok_c    : boolean                              := lane_c.data_byte_count = 1;
      constant loopback_c    : nsl_transceiver.lane.loopback_mode_t := lane_c.loopback;

      -- Which parts of the lane exist in the selected loopback mode. Hardware
      -- that the mode bypasses is not instantiated.
      --   RX SERDES path (pad, input_delay_variable, ISERDES, aligner): not in near end modes
      --   Decoder                                        : not in near end PCS
      --   TX path (encoder, OSERDES)                     : not in far end PMA
      --   TX pad                                         : always
      constant has_rx_serdes_c : boolean := loopback_c = nsl_transceiver.lane.LOOPBACK_NONE
                                            or loopback_c = nsl_transceiver.lane.LOOPBACK_FAR_END_PMA
                                            or loopback_c = nsl_transceiver.lane.LOOPBACK_FAR_END_PCS;
      constant has_decoder_c : boolean := loopback_c /= nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS;
      constant has_tx_c      : boolean := loopback_c /= nsl_transceiver.lane.LOOPBACK_FAR_END_PMA;

      -- Signals shared between the sections below. Each one is driven in
      -- every mode where it is read.
      signal s_data_p2m_se  : std_ulogic;  -- RX pad net, driven by the RX SERDES path
      signal s_pad_tx_se    : std_ulogic;  -- TX pad source
      signal s_enc2ser_code : nsl_line_coding.ibm_8b10b.code_word_t;  -- Driven by the TX path
      signal s_dec_code_in  : nsl_line_coding.ibm_8b10b.code_word_t;  -- Decoder input

      signal s_tx_symbol        : nsl_line_coding.ibm_8b10b.data_t;  -- From user
      signal s_dec_symbol       : nsl_line_coding.ibm_8b10b.data_t;  -- Decoder output
      signal s_dec_code_err     : std_ulogic;
      signal s_dec_disp_err     : std_ulogic;
      signal s_loop_symbol      : nsl_line_coding.ibm_8b10b.data_t;  -- Near end PCS loop register
      signal s_rx_symbol        : nsl_line_coding.ibm_8b10b.data_t;  -- To user
      signal s_code_err         : std_ulogic;
      signal s_disp_err         : std_ulogic;
      signal s_user_align_ready : std_ulogic;                        -- To user

    begin

      -- Lane checks
      assert encoding_ok_c report encoding_msg_c severity failure;
      encoding_check : nsl_synthesis.assertion.synth_assert
        generic map(message_c => encoding_msg_c, condition_c => encoding_ok_c)
        port map(unused_i     => '0');

      assert bytes_ok_c report byte_count_msg_c severity failure;
      bytes_check : nsl_synthesis.assertion.synth_assert
        generic map(message_c => byte_count_msg_c, condition_c => bytes_ok_c)
        port map(unused_i     => '0');

      s_tx_symbol.data    <= tx_m_i(lane_idx).data(0);
      s_tx_symbol.control <= tx_m_i(lane_idx).control(0);

      -- RX SERDES path ---------------------------------------------------------------------
      rx_serdes_path : if has_rx_serdes_c generate

        signal s_ser2dec_code : nsl_line_coding.ibm_8b10b.code_word_t;
        signal s_delay_shift  : std_ulogic;
        signal s_delay_mark   : std_ulogic;
        signal s_slip_shift   : std_ulogic;
        signal s_slip_mark    : std_ulogic;
        signal s_delayed_data : std_ulogic;
        signal s_align_ready  : std_ulogic;

      begin

        pad_diff_input_1 : nsl_io.pad.pad_diff_input
          generic map (
            diff_term => true,
            is_clock  => false,
            invert    => false)
          port map (
            p_diff => lane_rx_i(lane_idx),
            p_se   => s_data_p2m_se
            );

        delayer : nsl_io.delay.input_delay_variable
          port map(
            clock_i   => s_parallel_clock_buff,
            reset_n_i => s_general_reset_sync_n,
            mark_o    => s_delay_mark,
            shift_i   => s_delay_shift,
            data_i    => s_data_p2m_se,
            data_o    => s_delayed_data
            );

        serdes_ddr10_input_1 : nsl_io.serdes.serdes_ddr10_input
          generic map (
            left_to_right_c => false)
          port map (
            bit_clock_i  => s_serial_clock_buff,
            word_clock_i => s_parallel_clock_buff,
            reset_n_i    => s_general_reset_sync_n,
            serial_i     => s_delayed_data,
            parallel_o   => s_ser2dec_code,
            bitslip_i    => s_slip_shift,
            mark_o       => s_slip_mark
            );

        aligner : nsl_io.delay.input_delay_aligner
          generic map(
            stabilization_delay_c => 8,
            stabilization_cycle_c => 8
            )
          port map(
            clock_i   => s_parallel_clock_buff,
            reset_n_i => s_general_reset_sync_n,

            delay_shift_o  => s_delay_shift,
            delay_mark_i   => s_delay_mark,
            serdes_shift_o => s_slip_shift,
            serdes_mark_i  => s_slip_mark,

            restart_i => tx_m_i(lane_idx).control(2),
            valid_i   => tx_m_i(lane_idx).control(1),
            ready_o   => s_align_ready
            );

        s_user_align_ready <= s_align_ready;

        invert_in : if lane_c.polarity_invert_rx generate
          s_dec_code_in <= not s_ser2dec_code;
        end generate;

        not_invert_in : if not lane_c.polarity_invert_rx generate
          s_dec_code_in <= s_ser2dec_code;
        end generate;

      end generate;  -- rx_serdes_path

      -- Near end modes: the SERDES is bypassed, there is nothing to align
      no_rx_serdes_path : if not has_rx_serdes_c generate
      begin
        s_user_align_ready <= '1';
      end generate;

      -- Decoder ----------------------------------------------------------------------------
      decoder_path : if has_decoder_c generate
      begin
        ibm_8b10b_decoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
          generic map (
            implementation_c => "logic")
          port map (
            clock_i           => s_parallel_clock_buff,
            reset_n_i         => s_general_reset_sync_n,
            valid_i           => '1',
            data_i            => s_dec_code_in,
            data_o            => s_dec_symbol,
            code_error_o      => s_dec_code_err,
            disparity_error_o => s_dec_disp_err
            );
      end generate;

      -- Near end PMA: the decoder is fed by the encoder instead of the SERDES
      dec_in_loopback : if loopback_c = nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA generate
      begin
        s_dec_code_in <= s_enc2ser_code;
      end generate;

      -- RX symbol seen by the user ---------------------------------------------------------
      rx_user_loopback_pcs : if loopback_c = nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS generate
      begin
        loop_reg : process(s_parallel_clock_buff)
        begin
          if rising_edge(s_parallel_clock_buff) then
            s_loop_symbol <= s_tx_symbol;
          end if;
        end process;

        s_rx_symbol <= s_loop_symbol;
        s_code_err  <= '0';
        s_disp_err  <= '0';
      end generate;

      rx_user_decoder : if loopback_c /= nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS generate
      begin
        s_rx_symbol <= s_dec_symbol;
        s_code_err  <= s_dec_code_err;
        s_disp_err  <= s_dec_disp_err;
      end generate;

      -- TX path (encoder + OSERDES) --------------------------------------------------------
      tx_path : if has_tx_c generate

        signal s_enc_symbol             : nsl_line_coding.ibm_8b10b.data_t;  -- Encoder input
        signal s_enc2ser_processed_code : nsl_line_coding.ibm_8b10b.code_word_t;
        signal s_data_m2p_se            : std_ulogic;

      begin

        -- Encoder input: user, or the decoded RX symbol for far end PCS loopback
        enc_in_user : if loopback_c /= nsl_transceiver.lane.LOOPBACK_FAR_END_PCS generate
          s_enc_symbol <= s_tx_symbol;
        end generate;

        enc_in_loopback : if loopback_c = nsl_transceiver.lane.LOOPBACK_FAR_END_PCS generate
          s_enc_symbol <= s_dec_symbol;
        end generate;

        ibm_8b10b_encoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
          generic map (
            implementation_c => "logic")
          port map (
            clock_i   => s_parallel_clock_buff,
            reset_n_i => s_general_reset_sync_n,
            valid_i   => '1',
            data_i    => s_enc_symbol,
            data_o    => s_enc2ser_code
            );

        invert_out : if lane_c.polarity_invert_tx generate
          s_enc2ser_processed_code <= not s_enc2ser_code;
        end generate;

        not_invert_out : if not lane_c.polarity_invert_tx generate
          s_enc2ser_processed_code <= s_enc2ser_code;
        end generate;

        serdes_ddr10_output_1 : nsl_io.serdes.serdes_ddr10_output
          generic map (
            left_to_right_c => false)
          port map (
            bit_clock_i  => s_serial_clock_buff,
            word_clock_i => s_parallel_clock_buff,
            reset_n_i    => s_general_reset_sync_n,
            parallel_i   => s_enc2ser_processed_code,
            serial_o     => s_data_m2p_se
            );

        s_pad_tx_se <= s_data_m2p_se;

      end generate;  -- tx_path

      -- Far end PMA: the TX pad is fed by the RX pad net. The logical stream
      -- is what the RX path would decode, so the inversion is
      -- rx_invert xor tx_invert.
      pad_tx_far_pma : if loopback_c = nsl_transceiver.lane.LOOPBACK_FAR_END_PMA generate
      begin
        pol_same : if lane_c.polarity_invert_rx = lane_c.polarity_invert_tx generate
          s_pad_tx_se <= s_data_p2m_se;
        end generate;

        pol_diff : if lane_c.polarity_invert_rx /= lane_c.polarity_invert_tx generate
          s_pad_tx_se <= not s_data_p2m_se;
        end generate;
      end generate;

      -- TX pad: always present -------------------------------------------------------------
      pad_diff_output_1 : nsl_io.pad.pad_diff_output
        generic map (
          is_clock => false)
        port map (
          p_se   => s_pad_tx_se,
          p_diff => lane_tx_o(lane_idx)
          );

      -- Lane record outputs ------------------------------------------------------------------
      -- Clocks to the user
      lane_tx_clock_o(lane_idx) <= s_parallel_clock_buff;
      lane_rx_clock_o(lane_idx) <= s_parallel_clock_buff;

      tx_s_o(lane_idx).ready    <= s_everything_ready;
      tx_s_o(lane_idx).pll_lock <= s_domain_a_pll_locked;
      tx_s_o(lane_idx).status   <= (others => '0');

      rx_m_o(lane_idx).data <= (
        0      => s_rx_symbol.data,
        others => (others => '-')
        );
      rx_m_o(lane_idx).aux <= (
        0      => (0 => s_rx_symbol.control, 1 => s_code_err, 2 => s_disp_err, others => '0'),
        others => (others => '-')
        );
      rx_m_o(lane_idx).valid       <= '1';
      rx_m_o(lane_idx).pma_lock    <= s_everything_ready;
      rx_m_o(lane_idx).pcs_aligned <= s_user_align_ready;
      rx_m_o(lane_idx).elec_idle   <= '0';
      rx_m_o(lane_idx).status <= (
        0      => s_user_align_ready,
        1      => '0',  -- No clock correction for SERDES backend
        others => '-'
        );

    end generate;  -- lane_enabled

    lane_disabled : if not config_c.lanes(lane_idx).enabled generate
    begin
      lane_tx_o(lane_idx).p     <= '0';
      lane_tx_o(lane_idx).n     <= '1';
      lane_tx_clock_o(lane_idx) <= '0';
      lane_rx_clock_o(lane_idx) <= '0';
      tx_s_o(lane_idx)          <= nsl_transceiver.lane.null_tx_slave_c;
      rx_m_o(lane_idx)          <= nsl_transceiver.lane.null_rx_master_c;
    end generate;

  end generate;  -- lanes_gen

end architecture series7_serdes;
