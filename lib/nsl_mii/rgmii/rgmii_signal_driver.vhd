library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_mii, nsl_hwdep, nsl_clocking;
use nsl_mii.rgmii.all;

entity rgmii_signal_driver is
  port(
    phy_o : out rgmii_signal;
    phy_i : in  rgmii_signal;
    mac_o : out rgmii_pipe;
    mac_i : in  rgmii_pipe
    );
end entity;

architecture beh of rgmii_signal_driver is

  signal clock_to_phy: nsl_io.diff.diff_pair;
  signal error_xor_valid, error_to_phy: std_ulogic;
  signal valid_to_phy: std_ulogic;
  signal data_to_phy: std_ulogic_vector(7 downto 0);
  signal error_from_phy: std_ulogic;
  signal valid_from_phy: std_ulogic;
  signal clock_from_phy_se: std_ulogic;
  signal clock_from_phy: nsl_io.diff.diff_pair;
  signal mac_o_pre : rgmii_pipe;

  attribute period: string;
  attribute period of phy_i.c : signal is "8 ns";

begin

  -- Output side

  clock_to_phy.p <= mac_i.clock;
  clock_to_phy.n <= not mac_i.clock;
  error_xor_valid <= mac_i.error xor mac_i.valid;

  out_resync: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => 2,
      data_width_c => 10
      )
    port map(
      clock_i => mac_i.clock,
      data_i(7 downto 0) => mac_i.data,
      data_i(8) => mac_i.valid,
      data_i(9) => error_xor_valid,
      data_o(7 downto 0) => data_to_phy,
      data_o(8) => valid_to_phy,
      data_o(9) => error_to_phy
      );

  to_phy_clock: nsl_io.clock.clock_output_se_to_se
    port map(
      clock_i => mac_i.clock,
      port_o => phy_o.c
      );

  to_phy_data: nsl_io.ddr.ddr_bus_output
    generic map(
      ddr_width => 4
      )
    port map(
      clock_i => clock_to_phy,
      d_i => data_to_phy,
      dd_o => phy_o.d
      );

  to_phy_ctl: nsl_io.ddr.ddr_output
    port map(
      clock_i => clock_to_phy,
      d_i(0) => valid_to_phy,
      d_i(1) => error_to_phy,
      dd_o => phy_o.ctl
      );

  -- Input side
  
  from_phy_clock: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => phy_i.c,
      clock_o => clock_from_phy_se
      );

  clock_from_phy.p <= not clock_from_phy_se;
  clock_from_phy.n <= clock_from_phy_se;

  from_phy_data: nsl_io.ddr.ddr_bus_input
    generic map(
      ddr_width => 4
      )
    port map(
      clock_i => clock_from_phy,
      dd_i => phy_i.d,
      d_o => mac_o_pre.data
      );

  from_phy_ctl: nsl_io.ddr.ddr_input
    port map(
      clock_i => clock_from_phy,
      dd_i => phy_i.ctl,
      d_o(0) => valid_from_phy,
      d_o(1) => error_from_phy
      );

  mac_o_pre.valid <= valid_from_phy;
  mac_o_pre.error <= valid_from_phy xor error_from_phy;
  mac_o_pre.clock <= clock_from_phy_se;
  mac_o.clock <= clock_from_phy_se;

  resync: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => 2,
      data_width_c => 10
      )
    port map(
      clock_i => clock_from_phy_se,
      data_i(7 downto 0) => mac_o_pre.data,
      data_i(8) => mac_o_pre.valid,
      data_i(9) => mac_o_pre.error,
      data_o(7 downto 0) => mac_o.data,
      data_o(8) => mac_o.valid,
      data_o(9) => mac_o.error
      );
  
end architecture;
