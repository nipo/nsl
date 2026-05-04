library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_amba, nsl_data, nsl_simulation;

entity tb is
end;

architecture arch of tb is
  constant clock_period_c : time := 10 ns;
  constant cfg_c : nsl_amba.axi4_stream.config_t := nsl_amba.axi4_stream.config(bytes => 1, last => true);

  constant client_port_c: natural := 5000;
  constant server_port_c: natural := 5001;
  
  type uart_t is
  record
    tx : std_ulogic;
    cts: std_ulogic;
    rx : std_ulogic;
    rts: std_ulogic;
  end record;
  
  signal client_uart_s: uart_t;

  signal clock_s, reset_n_s: std_ulogic;
  
begin

  -- Client side:
  -- receives UART payloads and commands via UDP and sends the payloads through UART 
  client_side: block is
    signal client_rx_s, client_tx_s: nsl_amba.axi4_stream.bus_t;
  begin
    client_net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
      generic map(
        config_c => cfg_c,
        bind_port_c => client_port_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        tx_i => client_tx_s.m,
        tx_o => client_tx_s.s,

        rx_o => client_rx_s.m,
        rx_i => client_rx_s.s
        );

    client_rx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        prefix_c => "CLIENT RX",
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => client_rx_s
        );

    client_tx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        prefix_c => "CLIENT TX",
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => client_tx_s
        );
    
    client_dut : nsl_uart.transactor.axi4stream_cbor_uart_transactor
      generic map(
        system_clock_c => 10e7,
        stream_config_c => cfg_c,
        stop_count_c => 1,
        parity_c => nsl_uart.serdes.PARITY_NONE,
        handshake_active_c => '0',
        baud_rate_c => to_unsigned(9600, 24),
        timeout_c => to_unsigned(2, 24),
        bstr_max_size_c => 120
        )
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        tx_o  => client_uart_s.tx,
        cts_i => client_uart_s.cts,
        rx_i  => client_uart_s.rx,
        rts_o => client_uart_s.rts,

        cmd_i => client_rx_s.m,
        cmd_o => client_rx_s.s,
        rsp_o => client_tx_s.m,
        rsp_i => client_tx_s.s
        );
  end block;
  
  server_side: block is
    signal server_rx_s, server_tx_s: nsl_amba.axi4_stream.bus_t;
  begin
    server_dut : nsl_uart.transactor.axi4stream_cbor_uart_transactor
      generic map(
        system_clock_c => 10e7,
        stream_config_c => cfg_c,
        stop_count_c => 1,
        parity_c => nsl_uart.serdes.PARITY_NONE,
        handshake_active_c => '0',
        baud_rate_c => to_unsigned(9600, 24),
        timeout_c => to_unsigned(2, 24),
        bstr_max_size_c => 120
        )
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        tx_o  => client_uart_s.rx,
        cts_i => client_uart_s.rts,
        rx_i  => client_uart_s.tx,
        rts_o => client_uart_s.cts,

        cmd_i => server_rx_s.m,
        cmd_o => server_rx_s.s,
        rsp_o => server_tx_s.m,
        rsp_i => server_tx_s.s
        );

    server_net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
      generic map(
        config_c => cfg_c,
        bind_port_c => server_port_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        tx_i => server_tx_s.m,
        tx_o => server_tx_s.s,

        rx_o => server_rx_s.m,
        rx_i => server_rx_s.s
        );

    server_rx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        prefix_c => "SERVER RX",
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => server_rx_s
        );

    server_tx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        prefix_c => "SERVER TX",
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => server_tx_s
        );
  end block;
  
  driver : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c*8,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i(0) => '0'
      );

end architecture;
