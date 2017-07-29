library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;
use nsl.uart.all;

entity uart_framed_8n1 is
  generic(
    p_clk_rate : natural;
    baud_rate  : natural
    );
  port(
    p_resetn    : in std_ulogic;
    p_clk       : in std_ulogic;

    p_uart_tx   : out std_ulogic;
    p_uart_rx   : in  std_ulogic;

    p_tx_val  : in  nsl.framed.framed_req;
    p_tx_ack  : out nsl.framed.framed_ack;

    p_rx_val : out nsl.framed.framed_req;
    p_rx_ack : in  nsl.framed.framed_ack
    );
end entity;

architecture hier of uart_framed_8n1 is

begin

  tx: nsl.uart.uart_8n1_tx
    generic map(
      p_clk_rate => p_clk_rate,
      baud_rate => baud_rate
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_uart_tx => p_uart_tx,
      p_data => p_tx_val.data,
      p_ready => p_tx_ack.ack,
      p_data_val => p_tx_val.val
      );

  p_rx_val.more <= '0';
  
  rx: nsl.uart.uart_8n1_rx
    generic map(
      p_clk_rate => p_clk_rate,
      baud_rate => baud_rate
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_uart_rx => p_uart_rx,
      p_data => p_rx_val.data,
      p_data_val => p_rx_val.val
      );

end;
