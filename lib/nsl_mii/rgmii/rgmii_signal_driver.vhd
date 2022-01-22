library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_mii, nsl_hwdep, nsl_clocking;
use nsl_mii.rgmii.all;
use nsl_io.diff.all;

entity rgmii_signal_driver is
  generic(
    add_rx_delay_c: boolean := false;
    add_tx_delay_c: boolean := false
    );
  port(
    phy_o : out rgmii_signal;
    phy_i : in  rgmii_signal;
    mac_o : out rgmii_pipe;
    mac_i : in  rgmii_pipe
    );
end entity;

architecture beh of rgmii_signal_driver is

  signal tx_ref_clock_s: nsl_io.diff.diff_pair;
  signal tx_clock_fw_s, rx_clock_s: std_ulogic;
  signal rx_ref_clock_s: std_ulogic;
  signal rx_ref_clock_diff_s: nsl_io.diff.diff_pair;

  signal tx_rgmii_err_s, tx_rgmii_err_del_s: std_ulogic;
  signal tx_val_del_s: std_ulogic;
  signal tx_data_del_s: std_ulogic_vector(7 downto 0);

  signal rx_rgmii_err_s: std_ulogic;
  signal rx_rgmii_val_s: std_ulogic;
  signal rx_skewed_s : rgmii_signal;
  signal rx_pipe_pre_s : rgmii_pipe;

begin

  -- Output side
  tx_ref_clock_s <= to_diff(mac_i.clock);
  tx_rgmii_err_s <= mac_i.error xor mac_i.valid;

  out_resync: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => 2,
      data_width_c => 10
      )
    port map(
      clock_i => mac_i.clock,
      data_i(7 downto 0) => mac_i.data,
      data_i(8) => mac_i.valid,
      data_i(9) => tx_rgmii_err_s,
      data_o(7 downto 0) => tx_data_del_s,
      data_o(8) => tx_val_del_s,
      data_o(9) => tx_rgmii_err_del_s
      );

  tx_clock: nsl_io.clock.clock_output_se_to_se
    port map(
      clock_i => mac_i.clock,
      port_o => tx_clock_fw_s
      );

  has_tx_clock_delay: if add_tx_delay_c
  generate
    del: nsl_io.delay.output_delay_fixed
      generic map(
        delay_ps_c => 2000
        )
      port map(
        data_i => tx_clock_fw_s,
        data_o => phy_o.c
        );
  end generate;

  has_no_tx_clock_delay: if not add_tx_delay_c
  generate
    phy_o.c <= tx_clock_fw_s;
  end generate;

  tx_data: nsl_io.ddr.ddr_bus_output
    generic map(
      ddr_width => 4
      )
    port map(
      clock_i => tx_ref_clock_s,
      d_i => tx_data_del_s,
      dd_o => phy_o.d
      );

  tx_ctl: nsl_io.ddr.ddr_output
    port map(
      clock_i => tx_ref_clock_s,
      d_i(0) => tx_val_del_s,
      d_i(1) => tx_rgmii_err_del_s,
      dd_o => phy_o.ctl
      );

  -- Input side

  rx_clock_s <= not phy_i.c;

  from_phy_clock: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => rx_clock_s,
      clock_o => rx_ref_clock_s
      );

  rx_ref_clock_diff_s <= to_diff(rx_ref_clock_s);

  has_rx_delay: if add_rx_delay_c
  generate
    d: for i in 0 to 3
    generate
      del: nsl_io.delay.input_delay_fixed
        generic map(
          delay_ps_c => 2000
          )
        port map(
          data_i => phy_i.d(i),
          data_o => rx_skewed_s.d(i)
          );
    end generate;

    ctl: nsl_io.delay.input_delay_fixed
      generic map(
        delay_ps_c => 2000
        )
      port map(
        data_i => phy_i.ctl,
        data_o => rx_skewed_s.ctl
        );
  end generate;

  has_no_rx_delay: if not add_rx_delay_c
  generate
    rx_skewed_s <= phy_i;
  end generate;
  
  from_phy_data: nsl_io.ddr.ddr_bus_input
    generic map(
      ddr_width => 4
      )
    port map(
      clock_i => rx_ref_clock_diff_s,
      dd_i => rx_skewed_s.d,
      d_o => rx_pipe_pre_s.data
      );

  from_phy_ctl: nsl_io.ddr.ddr_input
    port map(
      clock_i => rx_ref_clock_diff_s,
      dd_i => rx_skewed_s.ctl,
      d_o(0) => rx_rgmii_val_s,
      d_o(1) => rx_rgmii_err_s
      );

  rx_pipe_pre_s.valid <= rx_rgmii_val_s;
  rx_pipe_pre_s.error <= rx_rgmii_val_s xor rx_rgmii_err_s;
  rx_pipe_pre_s.clock <= rx_ref_clock_s;
  mac_o.clock <= rx_ref_clock_s;

  resync: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => 2,
      data_width_c => 10
      )
    port map(
      clock_i => rx_ref_clock_s,
      data_i(7 downto 0) => rx_pipe_pre_s.data,
      data_i(8) => rx_pipe_pre_s.valid,
      data_i(9) => rx_pipe_pre_s.error,
      data_o(7 downto 0) => mac_o.data,
      data_o(8) => mac_o.valid,
      data_o(9) => mac_o.error
      );
  
end architecture;
