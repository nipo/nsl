library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_amba;

entity transceiver_group is
  generic(
    config_c : nsl_transceiver.group.config_t
    );
  port(
    reset_n_i : in std_ulogic;

    ref_clock_i : in nsl_io.diff.diff_pair_vector(0 to config_c.ref_clock_count-1);

    lane_tx_o : out nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);
    lane_rx_i : in nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);

    lane_tx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);
    lane_rx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);

    tx_m_i : in nsl_transceiver.lane.tx_master_vector(0 to config_c.lane_count-1);
    tx_s_o : out nsl_transceiver.lane.tx_slave_vector(0 to config_c.lane_count-1);
    rx_m_o : out nsl_transceiver.lane.rx_master_vector(0 to config_c.lane_count-1);
    rx_s_i : in nsl_transceiver.lane.rx_slave_vector(0 to config_c.lane_count-1);

    pma_reset_n_i : in std_ulogic_vector(0 to config_c.lane_count-1);

    apb_clock_i : in std_ulogic;
    apb_reset_n_i : in std_ulogic;
    apb_m_i : in nsl_amba.apb.master_t;
    apb_s_o : out nsl_amba.apb.slave_t
    );
end entity;

-- GW5A backend wrapping the GTR12_QUADB transceiver group
-- primitive. The primitive exposes a fixed 4-lane / 2-PLL /
-- 2-ref-clock shape; configurations that do not match are rejected
-- at elaboration.
architecture gw5a of transceiver_group is

begin

  assert config_c.lane_count = 4
    report "transceiver_group/gw5a: GTR12_QUADB primitive requires exactly 4 lanes"
    severity failure;
  assert config_c.pll_count <= 2
    report "transceiver_group/gw5a: GTR12_QUADB exposes at most 2 quad-shared PLLs (CMU0/CMU1)"
    severity failure;
  assert config_c.ref_clock_count <= 2
    report "transceiver_group/gw5a: GTR12_QUADB exposes at most 2 reference clock pairs"
    severity failure;
  assert nsl_transceiver.group.is_valid(config_c)
    report "transceiver_group/gw5a: configuration failed target-agnostic consistency check"
    severity failure;

  encoding_check: for lane_idx in 0 to config_c.lane_count-1 generate
    encoding_supported: if config_c.lanes(lane_idx).enabled generate
      assert config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_RAW
          or config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_8B10B
          or config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_64B66B
        report "transceiver_group/gw5a: lane encoding not supported by this backend yet"
        severity failure;
    end generate;
  end generate;

  -- Architecture body intentionally left for follow-up: GTR12_QUADB
  -- and GTR12_UPARA primitives are not yet instantiated; lane data
  -- and clock paths are not yet wired. Outputs are driven to safe
  -- defaults so an instance compiles and reports its config issues
  -- without claiming any datapath behaviour.
  lane_tie_off: for lane_idx in 0 to config_c.lane_count-1 generate
    lane_tx_o(lane_idx) <= (p => '0', n => '1');
    lane_tx_clock_o(lane_idx) <= '0';
    lane_rx_clock_o(lane_idx) <= '0';
    tx_s_o(lane_idx) <= nsl_transceiver.lane.null_tx_slave_c;
    rx_m_o(lane_idx) <= nsl_transceiver.lane.null_rx_master_c;
  end generate;

  apb_s_o <= (
    ready => '1',
    rdata => (others => (others => '0')),
    slverr => '0',
    wakeup => '0',
    ruser => (others => '0'),
    buser => (others => '0')
    );

end architecture;
