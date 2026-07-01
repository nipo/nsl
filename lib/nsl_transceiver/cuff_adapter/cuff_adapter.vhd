library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_cuff, nsl_line_coding, nsl_data;
use nsl_data.bytestream.all;

entity cuff_adapter is
  generic(
    lane_count_c : natural range 1 to 8;
    ibm_8b10b_implementation_c : string := "logic"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    tx_lane_i : in nsl_cuff.protocol.cuff_code_vector(0 to lane_count_c-1);
    rx_lane_o : out nsl_cuff.protocol.cuff_code_vector(0 to lane_count_c-1);

    tx_m_o : out nsl_transceiver.lane.tx_master_vector(0 to lane_count_c-1);
    tx_s_i : in nsl_transceiver.lane.tx_slave_vector(0 to lane_count_c-1);
    rx_m_i : in nsl_transceiver.lane.rx_master_vector(0 to lane_count_c-1);
    rx_s_o : out nsl_transceiver.lane.rx_slave_vector(0 to lane_count_c-1)
    );
end entity;

architecture beh of cuff_adapter is
begin

  lanes: for lane_idx in 0 to lane_count_c-1 generate

    signal s_decoded : nsl_line_coding.ibm_8b10b.data_t;
    signal s_encoder_in : nsl_line_coding.ibm_8b10b.data_t;

  begin

    tx_decoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
      generic map(
        implementation_c => ibm_8b10b_implementation_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        valid_i => '1',
        data_i => tx_lane_i(lane_idx),
        valid_o => open,
        data_o => s_decoded,
        code_error_o => open,
        disparity_error_o => open
        );

    tx_m_o(lane_idx) <= (
      data => (0 => s_decoded.data,
               others => (others => '-')),
      aux => (0 => (0 => s_decoded.control, others => '0'),
              others => (others => '-')),
      valid => '1',
      pcs_reset_n => reset_n_i,
      control => (others => '-'),
      control_h => (others => '-'),
      c2i_clock => '-'
      );

    s_encoder_in.data <= rx_m_i(lane_idx).data(0);
    s_encoder_in.control <= rx_m_i(lane_idx).aux(0)(0);

    rx_encoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
      generic map(
        implementation_c => ibm_8b10b_implementation_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        valid_i => '1',
        data_i => s_encoder_in,
        valid_o => open,
        data_o => rx_lane_o(lane_idx)
        );

    rx_s_o(lane_idx) <= (
      ready => '1',
      pcs_reset_n => reset_n_i,
      align_trigger => '0',
      chbond_start => '0',
      control => (others => '-')
      );

  end generate;

end architecture;
