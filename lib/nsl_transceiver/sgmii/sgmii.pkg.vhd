library ieee;
use ieee.std_logic_1164.all;

library nsl_transceiver, nsl_mii, nsl_io;
use nsl_mii.sgmii.all;
use nsl_transceiver.lane.all;

-- SGMII-side adapter for nsl_transceiver.cluster.transceiver_cluster.
-- Bridges nsl_sgmii vector (10-bit 8b/10b words and other control words) onto the
-- nsl_transceiver lane records (8-bit data + K flag, encoded by
-- the vendor transceiver primitive natively).
--
-- The adapter is rate-agnostic and clocks on the transceiver's
-- user clock. Data path uses lane.data_byte_count = 1

package sgmii is

  component sgmii_adapter is
    port (
      sgmii_i           : in  sgmii_m2p_vector;
      sgmii_o           : out sgmii_p2m_vector;
      tx_m_o            : out nsl_transceiver.lane.tx_master_vector;
      tx_s_i            : in  nsl_transceiver.lane.tx_slave_vector;
      rx_m_i            : in  nsl_transceiver.lane.rx_master_vector;
      rx_s_o            : out nsl_transceiver.lane.rx_slave_vector
      );
  end component;

end package sgmii;
