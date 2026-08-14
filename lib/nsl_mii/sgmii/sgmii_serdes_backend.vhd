library ieee;
use ieee.std_logic_1164.all;

library work, nsl_line_coding, nsl_io, nsl_logic;
use nsl_line_coding.ibm_8b10b.all;
use nsl_io.diff.all;
use nsl_io.pad.all;
use nsl_io.serdes.all;
use nsl_io.delay.all;
use work.sgmii.all;

entity sgmii_serdes_backend is
  port (
    reset_n_i  : in std_ulogic;
    clock125_i : in std_ulogic;
    clock625_i : in std_ulogic;

    sgmii_i : in  sgmii_m2p;
    sgmii_o : out sgmii_p2m;

    pair_diff_i : in  nsl_io.diff.diff_pair;
    pair_diff_o : out nsl_io.diff.diff_pair
    );
end entity sgmii_serdes_backend;

architecture beh of sgmii_serdes_backend is

  -- Internal signals
  signal s_data_m2p_se : std_ulogic;
  signal s_data_p2m_se : std_ulogic;

  signal s_ser2dec_code : nsl_line_coding.ibm_8b10b.code_word_t;
  signal s_enc2ser_code : nsl_line_coding.ibm_8b10b.code_word_t;

  signal s_delay_shift  : std_ulogic;
  signal s_delay_mark   : std_ulogic;
  signal s_slip_shift   : std_ulogic;
  signal s_slip_mark    : std_ulogic;
  signal s_delayed_data : std_ulogic;

begin  -- architecture beh

  -- Component instatiation
  -- RX side --------------------------------------------------------------------------------

  ibm_8b10b_decoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map (
      implementation_c => "logic")
    port map (
      clock_i           => clock125_i,
      reset_n_i         => sgmii_i.sys_reset_n,
      valid_i           => '1',
      data_i            => s_ser2dec_code,
      data_o            => sgmii_o.data_p2m_symbol,
      code_error_o      => sgmii_o.code_err,
      disparity_error_o => sgmii_o.disparity_err
      );

  aligner : nsl_io.delay.input_delay_aligner_slow
    generic map(
      stabilization_delay_c => 8,
      stabilization_cycle_c => 8
      )
    port map(
      clock_i   => clock125_i,
      reset_n_i => sgmii_i.sys_reset_n,

      delay_shift_o  => s_delay_shift,
      delay_mark_i   => s_delay_mark,
      serdes_shift_o => s_slip_shift,
      serdes_mark_i  => s_slip_mark,

      restart_i => sgmii_i.align_rst,
      valid_i   => sgmii_i.valid_symbol,
      ready_o   => sgmii_o.align_ready
      );

  delayer : nsl_io.delay.input_delay_variable
    port map(
      clock_i   => clock125_i,
      reset_n_i => sgmii_i.sys_reset_n,
      mark_o    => s_delay_mark,
      shift_i   => s_delay_shift,
      data_i    => s_data_p2m_se,
      data_o    => s_delayed_data
      );

  serdes_ddr10_input_1 : nsl_io.serdes.serdes_ddr10_input
    generic map (
      left_to_right_c => false)
    port map (
      bit_clock_i  => clock625_i,
      word_clock_i => clock125_i,
      reset_n_i    => sgmii_i.sys_reset_n,
      serial_i     => s_delayed_data,
      parallel_o   => s_ser2dec_code,
      bitslip_i    => s_slip_shift,
      mark_o       => s_slip_mark
      );

  pad_diff_input_1 : nsl_io.pad.pad_diff_input
    generic map (
      diff_term => true,
      is_clock  => false,
      invert    => false)
    port map (
      p_diff => pair_diff_i,
      p_se   => s_data_p2m_se
      );

  -- TX side --------------------------------------------------------------------------------

  ibm_8b10b_encoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map (
      implementation_c => "logic")
    port map (
      clock_i   => clock125_i,
      reset_n_i => sgmii_i.sys_reset_n,
      valid_i   => '1',
      data_i    => sgmii_i.data_m2p_symbol,
      data_o    => s_enc2ser_code
      );

  serdes_ddr10_output_1 : nsl_io.serdes.serdes_ddr10_output
    generic map (
      left_to_right_c => false)
    port map (
      bit_clock_i  => clock625_i,
      word_clock_i => clock125_i,
      reset_n_i    => sgmii_i.sys_reset_n,
      parallel_i   => s_enc2ser_code,
      serial_o     => s_data_m2p_se
      );

  pad_diff_output_1 : nsl_io.pad.pad_diff_output
    generic map (
      is_clock => false)
    port map (
      p_se   => s_data_m2p_se,
      p_diff => pair_diff_o
      );

end architecture beh;
