library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_uart;

entity uart_framed_8n1 is
  generic(
    divisor_width : natural range 1 to 20;
    bit_count_c : natural;
    stop_count_c : natural range 1 to 2;
    parity_c : nsl_uart.serdes.parity_t
    );
  port(
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;

    divisor_i   : in unsigned(divisor_width-1 downto 0);
    
    uart_o   : out std_ulogic;
    uart_i   : in  std_ulogic;

    tx_i  : in  nsl_bnoc.framed.framed_req;
    tx_o  : out nsl_bnoc.framed.framed_ack;

    rx_o : out nsl_bnoc.framed.framed_req;

    parity_ok_o     : out std_ulogic;
    break_o     : out std_ulogic
    );
end entity;

architecture hier of uart_framed_8n1 is

begin

  tx: nsl_uart.serdes.uart_tx
    generic map(
      divisor_width => divisor_width,
      bit_count_c => bit_count_c,
      stop_count_c => stop_count_c,
      parity_c => parity_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => divisor_i,
      uart_o => uart_o,

      data_i => tx_i.data,
      ready_o => rx_o.ready,
      valid_i => tx_i.valid
      );
  
  rx: nsl_uart.serdes.uart_rx
    generic map(
      divisor_width => divisor_width,
      bit_count_c => bit_count_c,
      stop_count_c => stop_count_c,
      parity_c => parity_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => divisor_i,
      uart_i => uart_i,

      data_o => rx_o.data,
      valid_o => rx_o.valid,

      parity_ok_o => parity_ok_o,
      break_o => break_o
      );

  rx_o.last <= '1';

end;
