library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_i2s, nsl_clocking;

entity tb is
end tb;

architecture arch of tb is

  signal done : std_ulogic_vector(0 to 0);
  constant data_width : integer := 9;
  signal reset_n, reset_n_async, clock : std_ulogic;
  signal ws, sck, sd : std_ulogic;
  signal src_channel, dst_channel : std_ulogic;
  signal src_ready, dst_valid : std_ulogic;
  signal src_data, dst_data : unsigned(data_width-1 downto 0);

begin
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 150 ns,
      reset_n_o(0) => reset_n,
      clock_o(0) => clock,
      done_i => done
      );

  transmitter: nsl_i2s.transmitter.i2s_transmitter_master
    port map(
      clock_i => clock,
      reset_n_i => reset_n,

      sck_div_m1_i => "111",

      sck_o => sck,
      ws_o => ws,
      sd_o => sd,

      ready_o => src_ready,
      channel_o => src_channel,
      data_i => src_data
      );

  receiver: nsl_i2s.receiver.i2s_receiver_slave
    port map(
      clock_i => clock,
      reset_n_i => reset_n,

      sck_i => sck,
      ws_i => ws,
      sd_i => sd,

      valid_o => dst_valid,
      channel_o => dst_channel,
      data_o => dst_data
      );

  data_gen: process
  begin
    done(0) <= '0';

    wait for 20 us;

    iter: for i in 0 to (2 ** data_width)-1
    loop
      src_data <= to_unsigned(i, data_width);
      re_wait: loop
        wait until rising_edge(clock);
        exit re_wait when src_ready = '1';
      end loop;
    end loop;

    wait for 10 us;
    done(0) <= '1';
    wait;
  end process;
  
end;
