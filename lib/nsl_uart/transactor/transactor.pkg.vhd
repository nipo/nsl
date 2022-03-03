library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_uart;

package transactor is

  component uart8 is
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
      cts_i  : in  std_ulogic := handshake_active_c;
      rx_i   : in  std_ulogic;
      rts_o  : out std_ulogic;

      tx_data_i  : in  nsl_bnoc.pipe.pipe_req_t;
      tx_data_o  : out nsl_bnoc.pipe.pipe_ack_t;
      rx_data_i  : in  nsl_bnoc.pipe.pipe_ack_t;
      rx_data_o  : out nsl_bnoc.pipe.pipe_req_t;

      parity_error_o : out std_ulogic;
      break_o     : out std_ulogic
      );
  end component;

end package transactor;
