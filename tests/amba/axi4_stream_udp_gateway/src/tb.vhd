library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal udp_rx_s, udp_tx_s, tb_tx_s, tb_rx_s: bus_t;

  constant cfg_c: config_t := config(4, last => true, keep => true);
  
begin

  rx: process
    variable rx_data : byte_stream;
    variable id, user, dest : std_ulogic_vector(1 to 0);
  begin
    done_s(0) <= '0';

    tb_rx_s.s <= accept(cfg_c, false);
    tb_tx_s.m <= transfer_defaults(cfg_c);

    wait for 100 ns;
    wait until falling_edge(clock_s);

    packet_receive(cfg_c, clock_s, tb_rx_s.m, tb_rx_s.s,
                   packet => rx_data,
                   id => id,
                   user => user,
                   dest => dest);

    wait until falling_edge(clock_s);

    packet_send(cfg_c, clock_s, tb_tx_s.s, tb_tx_s.m,
                packet => to_byte_string("Hello, world" & cr & lf));
    
    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;
  
  net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
    generic map(
      config_c => cfg_c,
      bind_port_c => 4242
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      tx_i => udp_tx_s.m,
      tx_o => udp_tx_s.s,

      rx_o => udp_rx_s.m,
      rx_i => udp_rx_s.s
      );

  udp2tb: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      depth_c => 16,
      config_c => cfg_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_s,
      reset_n_i => reset_n_s,

      in_i => udp_rx_s.m,
      in_o => udp_rx_s.s,

      out_o => tb_rx_s.m,
      out_i => tb_rx_s.s
      );

  tb2udp: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      depth_c => 16,
      config_c => cfg_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_s,
      reset_n_i => reset_n_s,

      in_i => tb_tx_s.m,
      in_o => tb_tx_s.s,

      out_o => udp_tx_s.m,
      out_i => udp_tx_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );
  
end;
