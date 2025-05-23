library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_spdif, nsl_logic, nsl_clocking, nsl_simulation, nsl_math, nsl_data, nsl_event;
use nsl_spdif.serdes.all;
use nsl_spdif.blocker.all;
use nsl_logic.logic.xor_reduce;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;

architecture arch of tb is

  signal s_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_async : std_ulogic;

  signal s_spdif, s_rx_tick : std_ulogic;
  signal s_transmitter_tick : std_ulogic;
  constant c_period: ufixed(4 downto -5) := to_ufixed(7.89, 4, -5);
  signal s_period: nsl_math.fixed.ufixed(5 downto -8);

  signal s_done : std_ulogic_vector(0 to 0);

  type data_t is
  record
    a, b: channel_data_t;
  end record;    

  signal s_tx_ready : std_ulogic;
  signal s_tx_block_ready : std_ulogic;
  signal s_tx_user, s_tx_channel_status : byte_string(0 to 23);
  signal s_tx_data : data_t;

  procedure spdif_frame_put(signal io_clk, io_spdif_ready : in std_ulogic;
                            signal io_data : out data_t;
                            constant audio_a, audio_b: unsigned(19 downto 0);
                            constant aux_a, aux_b: unsigned(3 downto 0)) is
  begin
    io_data.a.valid <= '1';
    io_data.a.audio <= audio_a;
    io_data.a.aux <= aux_a;
    io_data.b.valid <= '1';
    io_data.b.audio <= audio_b;
    io_data.b.aux <= aux_b;

    to_accepted: while true
    loop
      wait until rising_edge(io_clk);
      if io_spdif_ready = '1' then
        exit to_accepted;
      end if;
    end loop;
    wait until falling_edge(io_clk);
  end procedure;
  
begin

  reset_sync0: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk(0),
      clock_i => s_clk(0)
      );

  reset_sync1: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk(1),
      clock_i => s_clk(1)
      );

  freq_gen: nsl_event.tick.tick_generator
    port map(
      reset_n_i => s_resetn_clk(0),
      clock_i => s_clk(0),
      period_i => c_period,
      tick_o => s_transmitter_tick
      );
  
  transmitter: nsl_spdif.transceiver.spdif_tx
    port map(
      clock_i => s_clk(0),
      reset_n_i => s_resetn_clk(0),

      ui_tick_i => s_transmitter_tick,

      block_ready_o => s_tx_block_ready,
      block_user_i => s_tx_user,
      block_channel_status_i => s_tx_channel_status,

      ready_o => s_tx_ready,
      a_i => s_tx_data.a,
      b_i => s_tx_data.b,

      spdif_o => s_spdif
      );

  receiver: nsl_spdif.transceiver.spdif_rx_recovery
    generic map(
      clock_i_hz_c => 333333333,
      data_rate_c => 333333333 / 16 / 2
      )
    port map(
      clock_i => s_clk(1),
      reset_n_i => s_resetn_clk(1),
      
      spdif_i => s_spdif,
      ui_tick_o => s_rx_tick
      );

  measurer : nsl_event.tick.tick_measurer
    generic map(
      tau_c => 2**(1-s_period'right)-1
      )
    port map(
      clock_i => s_clk(1),
      reset_n_i => s_resetn_clk(1),
      tick_i => s_rx_tick,
      period_o => s_period
      );

  
  stim: process
  begin
    s_done <= "0";

    while true
    loop
      wait until rising_edge(s_clk(0));
      if s_resetn_clk(0) = '1' then
        exit;
      end if;
    end loop;

    s_tx_user <= (others => x"00");
    s_tx_channel_status <= from_hex("060c00020000000000000000000000000000000000000086");

    for i in 0 to 3
    loop
--      s_tx_channel_status(8 to 15) <= std_ulogic_vector(to_unsigned(i, 8));
      
      for frame in 0 to 191
      loop
        spdif_frame_put(s_clk(0), s_tx_ready, s_tx_data,
                        to_unsigned(frame, 20),
                        to_unsigned(16#da000# + frame, 20),
                        x"a", x"b");
      end loop;
    end loop;
      
    wait for 50 ns;
    s_done <= "1";
    wait;
  end process;
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 5 ns,
      clock_period(1) => 3000 ps,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o => s_clk,
      done_i => s_done
      );

end;
