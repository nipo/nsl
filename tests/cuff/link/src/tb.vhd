library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_cuff, nsl_data, nsl_io;
use nsl_cuff.protocol.all;
use nsl_cuff.link.all;
use nsl_io.diff.all;
use nsl_data.bytestream.all;

architecture arch of tb is

  signal bit_clock_s, clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  
  signal tx_link_s, rx_link_s : diff_pair_vector(0 to 3
                                                 );
  signal tx_lanes_s, rx_lanes_s : cuff_code_vector(tx_link_s'range);
  signal tx_data_s, rx_data_s : cuff_data_vector(tx_link_s'range);
  signal tx_state_s, rx_state_s: link_state_t;
  signal rx_align_restart_s : std_ulogic;
  signal rx_align_valid_s, rx_align_ready_s: std_ulogic_vector(tx_link_s'range);

begin

  tx_gen: process
  begin
    done_s(0) <= '0';
    tx_data_s <= (others => cuff_data_idle_c);

    wait for 180 us;
    
    done_s(0) <= '1';
    wait;
  end process;

  cuff_tx: nsl_cuff.link.link_transmitter
    generic map(
      lane_count_c => tx_link_s'length,
      mtu_l2_c => 6
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      data_i => tx_data_s,

      lane_o => tx_lanes_s,
      state_i => tx_state_s
      );

  cuff_media_tx: nsl_cuff.transceiver.cuff_diff_transmitter
    generic map(
      lane_count_c => tx_link_s'length
      )
    port map(
      reset_n_i => reset_n_s,
      bit_clock_i => bit_clock_s,
      clock_i => clock_s,

      lane_i => tx_lanes_s,
      pad_o => tx_link_s
      );

  tx_map: for i in tx_link_s'range
  generate
    inv: if (i mod 2) = 1
    generate
      rx_link_s(i).p <= transport tx_link_s(i).p after i * 4500 ps + (20 ns * (i mod 2));
      rx_link_s(i).n <= transport tx_link_s(i).n after i * 4500 ps + (20 ns * (i mod 2)) + 350 ps;
    end generate;

    ninv: if (i mod 2) = 0
    generate
      rx_link_s(i).n <= transport tx_link_s(i).p after i * 4500 ps + (20 ns * (i mod 2));
      rx_link_s(i).p <= transport tx_link_s(i).n after i * 4500 ps + (20 ns * (i mod 2)) + 350 ps;
    end generate;
  end generate;

  cuff_media_rx: nsl_cuff.transceiver.cuff_diff_receiver
    generic map(
      lane_count_c => tx_link_s'length
      )
    port map(
      reset_n_i => reset_n_s,
      bit_clock_i => bit_clock_s,
      clock_i => clock_s,

      lane_o => rx_lanes_s,
      pad_i => rx_link_s,

      align_restart_i => rx_align_restart_s,
      align_valid_i => rx_align_valid_s,
      align_ready_o => rx_align_ready_s
      );

  cuff_rx: nsl_cuff.link.link_receiver
    generic map(
      lane_count_c => tx_link_s'length,
      mtu_l2_c => 6
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      lane_i => rx_lanes_s,
      align_restart_o => rx_align_restart_s,
      align_valid_o => rx_align_valid_s,
      align_ready_i => rx_align_ready_s,
      
      data_o => rx_data_s,

      state_o => rx_state_s
      );

  tx_state_s <= rx_state_s;
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 20 ns,
      clock_period(1) => 4 ns,
      reset_duration(0) => 14 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      clock_o(1) => bit_clock_s,
      done_i => done_s
      );

end;
