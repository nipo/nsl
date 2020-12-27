library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_mii, nsl_hwdep;
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
  signal error_to_phy: std_ulogic;
  signal error_from_phy: std_ulogic;
  signal valid_from_phy: std_ulogic;
  signal clock_from_phy_se: std_ulogic;
  signal clock_from_phy: nsl_io.diff.diff_pair;
  
begin

  -- Output side

  clock_to_phy.p <= mac_i.clock;
  clock_to_phy.n <= not mac_i.clock;
  error_to_phy <= mac_i.error xor mac_i.valid;

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
      d_i => mac_i.data,
      dd_o => phy_o.d
      );

  to_phy_ctl: nsl_io.ddr.ddr_output
    port map(
      clock_i => clock_to_phy,
      d_i(0) => mac_i.valid,
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
      d_o => mac_o.data
      );

  from_phy_ctl: nsl_io.ddr.ddr_input
    port map(
      clock_i => clock_from_phy,
      dd_i => phy_i.ctl,
      d_o(0) => valid_from_phy,
      d_o(1) => error_from_phy
      );

  mac_o.valid <= valid_from_phy;
  mac_o.error <= valid_from_phy xor error_from_phy;
  mac_o.clock <= clock_from_phy_se;
  
end architecture;
