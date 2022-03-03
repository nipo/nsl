library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_uart;

entity uart8 is
  generic(
    stop_count_c : natural range 1 to 2 := 1;
    parity_c : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_NONE;
    handshake_active_c : std_ulogic := '0'
    );
  port(
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;

    divisor_i   : in unsigned;
    
    tx_o   : out std_ulogic;
    cts_i  : in std_ulogic := handshake_active_c;
    rx_i   : in  std_ulogic;
    rts_o  : out std_ulogic;

    tx_data_i  : in  nsl_bnoc.pipe.pipe_req_t;
    tx_data_o  : out nsl_bnoc.pipe.pipe_ack_t;
    rx_data_i  : in  nsl_bnoc.pipe.pipe_ack_t;
    rx_data_o  : out nsl_bnoc.pipe.pipe_req_t;

    parity_error_o : out std_ulogic;
    break_o     : out std_ulogic
    );
end entity;

architecture hier of uart8 is

begin

  tx: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => nsl_bnoc.pipe.pipe_data_t'length,
      stop_count_c => stop_count_c,
      parity_c => parity_c,
      rtr_active_c => handshake_active_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => divisor_i,

      uart_o => tx_o,
      rtr_i => cts_i,

      data_i => tx_data_i.data,
      ready_o => tx_data_o.ready,
      valid_i => tx_data_i.valid
      );

  rx: nsl_uart.serdes.uart_rx
    generic map(
      bit_count_c => nsl_bnoc.pipe.pipe_data_t'length,
      stop_count_c => stop_count_c,
      parity_c => parity_c,
      rts_active_c => handshake_active_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => divisor_i,

      uart_i => rx_i,
      rts_o => rts_o,

      data_o => rx_data_o.data,
      valid_o => rx_data_o.valid,
      ready_i => rx_data_i.ready,

      parity_error_o => parity_error_o,
      break_o => break_o
      );

end;
