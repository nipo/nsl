library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_mii, nsl_data;
use nsl_mii.rgmii.all;
use nsl_mii.mii.all;
use nsl_mii.testing.all;
use nsl_data.bytestream.all;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 3);
  signal rgmii2mii_s, mii2rgmii_s : nsl_bnoc.committed.committed_bus;
  signal rgmii2mii_atomic_s, mii2rgmii_atomic_s : nsl_bnoc.committed.committed_bus;
  signal rgmii_s : rgmii_io;
  signal mii_s : mii_io;

begin

  rgmii_gen: process
    constant mode: rgmii_mode_t := RGMII_MODE_10;
  begin
    done_s(0) <= '0';

    rgmii_put_init(rgmii_s.p2m);
    rgmii_interframe_put(rgmii_s.p2m, 1024, mode);

    rgmii_frame_put(rgmii_s.p2m,
                    data => from_hex("40302010"),
                    mode => mode);

    rgmii_interframe_put(rgmii_s.p2m, 1024, mode);

    done_s(0) <= '1';
    wait;
  end process;

  mii_chk: process
    variable blob: nsl_data.bytestream.byte_stream;
    constant rate: natural := 100;
  begin
    done_s(1) <= '0';

    mii_tx_init(mii_s.p2m.tx);
    mii_frame_check("MII", mii_s.p2m.tx, mii_s.m2p.tx, from_hex("40302010"), true, rate);
    wait for 1 us;

    done_s(1) <= '1';
    wait;
  end process;

  mii_gen: process
    constant rate: natural := 100;
  begin
    done_s(2) <= '0';

    mii_rx_init(mii_s.p2m.rx);
    mii_interframe_put(mii_s.p2m.rx, 512, rate);
    mii_frame_put(mii_s.p2m.rx,
                  data => from_hex("10203040"),
                  rate => rate);

    mii_interframe_put(mii_s.p2m.rx, 1024, rate);

    done_s(2) <= '1';
    wait;
  end process;

  rgmii_chk: process
    variable blob: nsl_data.bytestream.byte_stream;
    constant mode: rgmii_mode_t := RGMII_MODE_10;
  begin
    done_s(3) <= '0';

    rgmii_frame_check("RGMII", rgmii_s.m2p, from_hex("10203040"), true, mode);
    wait for 1 us;

    done_s(3) <= '1';
    wait;
  end process;

  rgmii: nsl_mii.rgmii.rgmii_driver
    generic map(
      rx_clock_delay_ps_c => 0,
      tx_clock_delay_ps_c => 0,
      inband_status_c => false
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      rgmii_o => rgmii_s.m2p,
      rgmii_i => rgmii_s.p2m,

      rx_o => rgmii2mii_s.req,
      rx_i => rgmii2mii_s.ack,

      tx_i => mii2rgmii_atomic_s.req,
      tx_o => mii2rgmii_atomic_s.ack
      );

  r2m_atomic: nsl_bnoc.framed.framed_fifo_atomic
    generic map(
      depth => 1024,
      txn_depth => 4,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_s,
      p_clk(0) => clock_s,

      p_in_val => rgmii2mii_s.req,
      p_in_ack => rgmii2mii_s.ack,

      p_out_val => rgmii2mii_atomic_s.req,
      p_out_ack => rgmii2mii_atomic_s.ack
      );

  m2r_atomic: nsl_bnoc.framed.framed_fifo_atomic
    generic map(
      depth => 1024,
      txn_depth => 4,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_s,
      p_clk(0) => clock_s,

      p_in_val => mii2rgmii_s.req,
      p_in_ack => mii2rgmii_s.ack,

      p_out_val => mii2rgmii_atomic_s.req,
      p_out_ack => mii2rgmii_atomic_s.ack
      );
  
  mii: nsl_mii.mii.mii_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      mii_o => mii_s.m2p,
      mii_i => mii_s.p2m,

      rx_o => mii2rgmii_s.req,
      rx_i => mii2rgmii_s.ack,

      tx_i => rgmii2mii_atomic_s.req,
      tx_o => rgmii2mii_atomic_s.ack
      );      
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 14 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
