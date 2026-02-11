library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_uart, nsl_clocking;

entity uart8_no_generics is
  port(
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;

    divisor_i   : in unsigned;
    
    tx_o   : out std_ulogic;
    cts_i  : in std_ulogic := '0';
    rx_i   : in  std_ulogic;
    rts_o  : out std_ulogic;

    cts_o  : out std_ulogic;
    rx_o   : out std_ulogic;
    
    tx_data_i : in  nsl_bnoc.pipe.pipe_req_t;
    tx_data_o : out nsl_bnoc.pipe.pipe_ack_t;
    rx_data_i : in  nsl_bnoc.pipe.pipe_ack_t;
    rx_data_o : out nsl_bnoc.pipe.pipe_req_t;

    parity_error_o : out std_ulogic;
    break_o        : out std_ulogic;

    stop_count_i       : in unsigned(1 downto 0);
    parity_i           : in unsigned(1 downto 0);
    handshake_active_i : in std_ulogic := '0'
    );
end entity;

architecture hier of uart8_no_generics is

  signal rx_s, cts_s: std_ulogic;
  
begin

  rx_resync: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 2
      )
    port map(
      clock_i => clock_i,
      data_i(0) => rx_i,
      data_i(1) => cts_i,
      data_o(0) => rx_s,
      data_o(1) => cts_s
      );

  rx_o <= rx_s;
  cts_o <= cts_s;
  
  tx: nsl_uart.serdes.uart_tx_no_generics
    generic map(
      bit_count_c => nsl_bnoc.pipe.pipe_data_t'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => divisor_i,

      uart_o => tx_o,
      rtr_i => cts_s,

      data_i => tx_data_i.data,
      ready_o => tx_data_o.ready,
      valid_i => tx_data_i.valid,
    
      stop_count_i => stop_count_i,
      parity_i     => parity_i,
      rtr_active_i => handshake_active_i
      );

  rx: nsl_uart.serdes.uart_rx_no_generics
    generic map(
      bit_count_c => nsl_bnoc.pipe.pipe_data_t'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => divisor_i,

      uart_i => rx_s,
      rts_o => rts_o,

      data_o => rx_data_o.data,
      valid_o => rx_data_o.valid,
      ready_i => rx_data_i.ready,

      parity_error_o => parity_error_o,
      break_o => break_o,
      
      stop_count_i => stop_count_i,
      parity_i     => parity_i,
      rts_active_i => handshake_active_i
      );

end;
