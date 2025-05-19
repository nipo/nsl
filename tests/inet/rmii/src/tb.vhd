library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_mii, nsl_data;
use nsl_mii.mii.all;
use nsl_mii.rmii.all;
use nsl_mii.link.all;
use nsl_mii.testing.all;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);
  signal lb_i_s, lb_o_s : nsl_bnoc.committed.committed_bus;
  signal rmii_s : rmii_io;

begin
  
  rmii_gen: process
  begin
    done_s(0) <= '0';

    rmii_init(rmii_s.p2m);
    for i in 0 to 2
    loop
      rmii_interframe_put(rmii_s.ref_clk, rmii_s.p2m, 1024);
      rmii_frame_put(rmii_s.ref_clk, rmii_s.p2m,
                     data => from_hex("40302010"));
    end loop;
    rmii_interframe_put(rmii_s.ref_clk, rmii_s.p2m, 1024);
    rmii_frame_put(rmii_s.ref_clk, rmii_s.p2m,
                   data => from_hex("40302010"),
                   error_at_bit => 2);
    rmii_interframe_put(rmii_s.ref_clk, rmii_s.p2m, 1024);

    done_s(0) <= '1';
    wait;
  end process;

  rmii_chk: process
    variable blob: nsl_data.bytestream.byte_stream;
    constant speed: link_speed_t := link_speed_100;

    variable rx_data: byte_stream := new byte_string(1 to 0);
    variable rx_valid: boolean;
  begin
    done_s(1) <= '0';

    for i in 0 to 2
    loop
      rmii_frame_check("RMII", rmii_s.ref_clk, rmii_s.m2p, from_hex("40302010"), true, level => log_level_fatal);
    end loop;
    rmii_frame_get(rmii_s.ref_clk, rmii_s.m2p, rx_data, rx_valid, speed);

    assert rx_data.all /= from_hex("40302010") or not rx_valid
      report "Should have had bad data"
      severity failure;

    
    done_s(1) <= '1';
    wait;
  end process;

  loopback_atomic: nsl_bnoc.framed.framed_fifo_atomic
    generic map(
      depth => 1024,
      txn_depth => 4,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_s,
      p_clk(0) => clock_s,

      p_in_val => lb_i_s.req,
      p_in_ack => lb_i_s.ack,

      p_out_val => lb_o_s.req,
      p_out_ack => lb_o_s.ack
      );
  
  rmii_driver: nsl_mii.rmii.rmii_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      rmii_ref_clock_i => rmii_s.ref_clk,
      rmii_o => rmii_s.m2p,
      rmii_i => rmii_s.p2m,

      rx_o => lb_i_s.req,
      rx_i => lb_i_s.ack,

      tx_i => lb_o_s.req,
      tx_o => lb_o_s.ack
      );      
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      clock_period(1) => 20 ns,
      reset_duration(0) => 14 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      clock_o(1) => rmii_s.ref_clk,
      done_i => done_s
      );

end;
