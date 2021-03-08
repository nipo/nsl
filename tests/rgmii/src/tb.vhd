library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_simulation, nsl_mii;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_clk : std_ulogic_vector(0 to 1);
  signal rx_clock : std_ulogic;
  signal s_done : std_ulogic_vector(0 to 1);

  signal n_val : nsl_bnoc.framed.framed_req_array(0 to 2);
  signal n_ack : nsl_bnoc.framed.framed_ack_array(0 to 2);

  signal phy_data, phy_data_rx, phy_data_del : nsl_mii.rgmii.rgmii_pipe;
  signal phy_tx, phy_tx_rx : nsl_mii.rgmii.rgmii_signal;
  
begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => s_clk'length,
      reset_count => s_resetn_clk'length,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 8 ns,
      reset_duration(0) => 15 ns,
      reset_duration(1) => 12 ns,
      reset_n_o => s_resetn_clk,
      clock_o => s_clk,
      done_i => s_done
      );

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "frame.txt"
      )
    port map(
      p_resetn => s_resetn_clk(0),
      p_clk => s_clk(0),
      p_out_val => n_val(0),
      p_out_ack => n_ack(0),
      p_done => s_done(0)
      );

  fifo: nsl_bnoc.framed.framed_fifo_atomic
    generic map(
      clk_count => s_clk'length,
      depth => 512
      )
    port map(
      p_resetn => s_resetn_clk(0),
      p_clk => s_clk,
      p_in_val => n_val(0),
      p_in_ack => n_ack(0),
      p_out_val => n_val(1),
      p_out_ack => n_ack(1)
      );

  to_mii: nsl_mii.rgmii.rgmii_from_framed
    port map(
      reset_n_i => s_resetn_clk(1),
      clock_i => s_clk(1),

      framed_i => n_val(1),
      framed_o => n_ack(1),

      rgmii_o => phy_data
      );

  phy_data_del <= phy_data after 1 ns;
  phy_tx_rx.c <= phy_tx.c after 2 ns;
  phy_tx_rx.d <= phy_tx.d;
  phy_tx_rx.ctl <= phy_tx.ctl;
  
  mii_driver: nsl_mii.rgmii.rgmii_signal_driver
    port map(
      phy_o => phy_tx,
      phy_i => phy_tx_rx,

      mac_i => phy_data_del,
      mac_o => phy_data_rx
      );
  
  from_mii: nsl_mii.rgmii.rgmii_to_framed
    port map(
      reset_n_i => s_resetn_clk(1),
      clock_o => rx_clock,

      framed_o => n_val(2),
      framed_i => n_ack(2),

      rgmii_i => phy_data_rx
      );

  wait_end: process
  begin
    s_done(1) <= '0';
    wait for 24000 ns;
    s_done(1) <= '1';
    wait;
  end process;
  
end;
