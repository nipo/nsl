library ieee;
use ieee.std_logic_1164.all;

library nsl_transceiver, nsl_cuff;

-- CUFF-side adapter for nsl_transceiver.cluster.transceiver_cluster.
-- Bridges nsl_cuff.protocol.cuff_code_vector (10-bit 8b/10b words
-- native to nsl_cuff's ISERDES/OSERDES transceiver) onto the
-- nsl_transceiver lane records (8-bit data + K flag, encoded by
-- the vendor transceiver primitive natively).
--
-- The adapter is rate-agnostic and clocks on the transceiver's
-- user clock. Data path uses lane.data_byte_count = 1 (one byte
-- per lane per fabric cycle), matching CUFF's word-per-cycle
-- contract.
package cuff_adapter is

  component cuff_adapter is
    generic(
      lane_count_c : natural range 1 to 8;
      ibm_8b10b_implementation_c : string := "logic"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- CUFF-side. tx_lane_i comes from nsl_cuff.lane.lane_transmitter,
      -- rx_lane_o feeds nsl_cuff.lane.lane_receiver.
      tx_lane_i : in nsl_cuff.protocol.cuff_code_vector(0 to lane_count_c-1);
      rx_lane_o : out nsl_cuff.protocol.cuff_code_vector(0 to lane_count_c-1);

      -- Transceiver-side. Wires onto
      -- nsl_transceiver.cluster.transceiver_cluster's lane records.
      tx_m_o : out nsl_transceiver.lane.tx_master_vector(0 to lane_count_c-1);
      tx_s_i : in nsl_transceiver.lane.tx_slave_vector(0 to lane_count_c-1);
      rx_m_i : in nsl_transceiver.lane.rx_master_vector(0 to lane_count_c-1);
      rx_s_o : out nsl_transceiver.lane.rx_slave_vector(0 to lane_count_c-1)
      );
  end component;

end package cuff_adapter;
