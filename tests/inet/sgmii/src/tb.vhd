library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_mii, nsl_data, nsl_io;
use nsl_mii.mii.all;
use nsl_mii.sgmii.all;
use nsl_mii.link.all;
use nsl_io.diff.all;
use nsl_mii.testing.all;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;
use nsl_bnoc.testing.all;

architecture arch of tb is

  signal clock125_s, clock625_s, reset_n_s      : std_ulogic;
  signal clock125_delayed_s, clock625_delayed_s : std_ulogic;
  signal done_s                                 : std_ulogic_vector(1 downto 0);
  signal committed_i_s1, committed_o_s1         : nsl_bnoc.committed.committed_bus;
  signal committed_i_s2, committed_o_s2         : nsl_bnoc.committed.committed_bus;
  signal sgmii_m2p1, sgmii_m2p2                 : nsl_mii.sgmii.sgmii_m2p;
  signal sgmii_p2m1, sgmii_p2m2                 : nsl_mii.sgmii.sgmii_p2m;
  signal data_diff_tx_1                         : nsl_io.diff.diff_pair;
  signal data_diff_rx_1                         : nsl_io.diff.diff_pair;
  signal data_diff_tx_2                         : nsl_io.diff.diff_pair;
  signal data_diff_rx_2                         : nsl_io.diff.diff_pair;

  constant frame_tx_1_c : byte_string := from_hex(
    "02000000feed00deadbeef"
    );

  constant clk_delay_c  : time := 3 ns;
  constant data_delay_c : time := 2 ns;

begin

  sgmii_gen : process
  begin
    done_s(0) <= '0';

    committed_put(committed_o_s1.req, committed_o_s1.ack, clock125_s,
                  frame_tx_1_c, true);

    committed_wait(committed_o_s1.req, committed_o_s1.ack, clock125_s, 2048);

    done_s(0) <= '1';
    wait;
  end process;

  sgmii_check : process
  begin
    done_s(1) <= '0';

    committed_check("Check 1", committed_i_s2.req, committed_i_s2.ack, clock125_delayed_s,
                  frame_tx_1_c, true, LOG_LEVEL_FATAL);

    done_s(1) <= '1';
    wait;
  end process;

  -- SGMII number 1
  sgmii_driver_1 : nsl_mii.sgmii.sgmii_driver
    generic map (
      link_timer_c => 30  -- Faster simulation than the spec default
      )
    port map (
      reset_n_i    => reset_n_s,
      clock_i      => clock125_s,
      sgmii_o      => sgmii_m2p1,
      sgmii_i      => sgmii_p2m1,
      link_speed_i => LINK_SPEED_1000,
      rx_o         => committed_i_s1.req,
      rx_i         => committed_i_s1.ack,
      tx_i         => committed_o_s1.req,
      tx_o         => committed_o_s1.ack
      );

  sgmii_serdes_backend_1 : nsl_mii.sgmii.sgmii_serdes_backend
    port map (
      reset_n_i   => reset_n_s,
      clock125_i  => clock125_s,
      clock625_i  => clock625_s,
      sgmii_i     => sgmii_m2p1,
      sgmii_o     => sgmii_p2m1,
      pair_diff_i => data_diff_rx_1,
      pair_diff_o => data_diff_tx_1
      );

  -- SGMII number 2
  sgmii_driver_2 : nsl_mii.sgmii.sgmii_driver
    generic map (
      link_timer_c => 30  -- Faster simulation than the spec default
      )    
    port map (
      reset_n_i    => reset_n_s,
      clock_i      => clock125_delayed_s,
      sgmii_o      => sgmii_m2p2,
      sgmii_i      => sgmii_p2m2,
      link_speed_i => LINK_SPEED_1000,
      rx_o         => committed_i_s2.req,
      rx_i         => committed_i_s2.ack,
      tx_i         => committed_o_s2.req,
      tx_o         => committed_o_s2.ack
      );

  sgmii_serdes_backend_2 : nsl_mii.sgmii.sgmii_serdes_backend
    port map (
      reset_n_i   => reset_n_s,
      clock125_i  => clock125_delayed_s,
      clock625_i  => clock625_delayed_s,
      sgmii_i     => sgmii_m2p2,
      sgmii_o     => sgmii_p2m2,
      pair_diff_i => data_diff_rx_2,
      pair_diff_o => data_diff_tx_2
      );

  -- Created delayed clock for SGMII driver 2
  -- This simulates having different system clocks
  -- between the two SGMII modules
  clock125_delayed_s <= transport clock125_s after clk_delay_c;
  clock625_delayed_s <= transport clock625_s after clk_delay_c;

  -- Connect the two SGMII together with propagation delay
  data_diff_rx_2 <= transport data_diff_tx_1 after data_delay_c;

  data_diff_rx_1 <= transport data_diff_tx_2 after data_delay_c;

  driver : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count  => done_s'length
      )
    port map(
      clock_period(0)   => 8 ns,        -- 125MHz clock for GMII
      clock_period(1)   => 1600 ps,     -- 625MHz clock for SGMII
      reset_duration(0) => 14 ns,
      reset_n_o(0)      => reset_n_s,
      clock_o(0)        => clock125_s,
      clock_o(1)        => clock625_s,
      done_i            => done_s
      );

end;
