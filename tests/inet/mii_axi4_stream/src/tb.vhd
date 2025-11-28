library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_mii, nsl_data, nsl_amba, nsl_simulation;
use nsl_mii.rgmii.all;
use nsl_mii.link.all;
use nsl_mii.mii.all;
use nsl_mii.testing.all;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_simulation.logging.all;
use nsl_mii.flit.all;

architecture arch of tb is

  signal clock_s, reset_n_s, error_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 3);
  signal rgmii2mii_s, mii2rgmii_s : bus_t;
  signal rgmii2mii_clean_s, mii2rgmii_clean_s, mii2rgmii_prefilled_s : bus_t;
  signal rgmii_s : rgmii_io;
  signal mii_s : mii_io;

begin

  rgmii_gen: process
    constant speed: link_speed_t := LINK_SPEED_1000;
  begin
    done_s(0) <= '0';

    rgmii_put_init(rgmii_s.p2m);
    rgmii_interframe_put(rgmii_s.p2m, 1024, speed);

    rgmii_frame_put(rgmii_s.p2m,
                    data => from_hex("40302010"),
                    speed => speed);

    rgmii_interframe_put(rgmii_s.p2m, 1024, speed);

    done_s(0) <= '1';
    wait;
  end process;

  mii_chk: process
    variable blob: nsl_data.bytestream.byte_stream;
    constant speed: link_speed_t := LINK_SPEED_100;
  begin
    done_s(1) <= '0';

    mii_tx_init(mii_s.p2m.tx);
    mii_frame_check("MII", mii_s.p2m.tx, mii_s.m2p.tx, from_hex("40302010"), true, speed);
    wait for 1 us;

    done_s(1) <= '1';
    wait;
  end process;

  mii_gen: process
    constant speed: link_speed_t := LINK_SPEED_100;
  begin
    done_s(2) <= '0';

    mii_rx_init(mii_s.p2m.rx);
    mii_interframe_put(mii_s.p2m.rx, 512, speed);
    mii_frame_put(mii_s.p2m.rx,
                  data => from_hex("10203040"),
                  speed => speed);

    mii_interframe_put(mii_s.p2m.rx, 1024, speed);

    done_s(2) <= '1';
    wait;
  end process;

  rgmii_chk: process
    variable blob: nsl_data.bytestream.byte_stream;
    constant speed: link_speed_t := LINK_SPEED_1000;
  begin
    done_s(3) <= '0';
    rgmii_frame_check("RGMII", rgmii_s.m2p, from_hex("10203040"), true, speed);
    wait for 1 us;

    done_s(3) <= '1';
    wait;
  end process;

  dut: nsl_mii.rgmii.rgmii_axi4_stream_driver
    generic map(
      rx_clock_delay_ps_c => 0,
      tx_clock_delay_ps_c => 0
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      
      rgmii_o => rgmii_s.m2p,
      rgmii_i => rgmii_s.p2m,

      mode_i => LINK_SPEED_1000,

      rx_sfd_o => open,
      tx_sfd_o => open,
      rx_clock_o => open,
      rx_flit_o => open,

      rx_o => rgmii2mii_s.m,
      rx_i => rgmii2mii_s.s,

      tx_i => mii2rgmii_prefilled_s.m,
      tx_o => mii2rgmii_prefilled_s.s
      );

  error_s <= user(axi4_flit_cfg, rgmii2mii_s.m)(0);

  rgmii2mii_cleaner : nsl_amba.stream_fifo.axi4_stream_fifo_clean
    generic map (
        config_c => axi4_flit_cfg
    )
    port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        in_error_i => error_s,
        in_i => rgmii2mii_s.m,
        in_o => rgmii2mii_s.s,

        out_o => rgmii2mii_clean_s.m,
        out_i => rgmii2mii_clean_s.s
    );

  m2r_prefill_buffer: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
    generic map (
      config_c => axi4_flit_cfg,
      prefill_count_c => 16
    )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => mii2rgmii_clean_s.m,
      in_o => mii2rgmii_clean_s.s,

      out_o => mii2rgmii_prefilled_s.m,
      out_i => mii2rgmii_prefilled_s.s
      );
  
  mii2rgmii_cleaner : nsl_amba.stream_fifo.axi4_stream_fifo_clean
    generic map (
        config_c => axi4_flit_cfg
    )
    port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        in_error_i => error_s,
        in_i => mii2rgmii_s.m,
        in_o => mii2rgmii_s.s,

        out_o => mii2rgmii_clean_s.m,
        out_i => mii2rgmii_clean_s.s
    );

  mii: nsl_mii.mii.mii_axi_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      mii_o => mii_s.m2p,
      mii_i => mii_s.p2m,

      rx_o => mii2rgmii_s.m,
      rx_i => mii2rgmii_s.s,

      tx_i => rgmii2mii_clean_s.m,
      tx_o => rgmii2mii_clean_s.s
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
