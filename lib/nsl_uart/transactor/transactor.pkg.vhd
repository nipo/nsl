library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_uart;

package transactor is

  component uart_framed_8n1 is
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

      parity_ok_o : out std_ulogic;
      break_o     : out std_ulogic
      );
  end component;

end package transactor;
