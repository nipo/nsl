library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.flit.all;
use nsl.fifo.all;
use nsl.noc.all;
use nsl.uart.all;

entity uart_noc_8n1 is
  generic(
    p_clk_rate : natural;
    baud_rate  : natural;
    srcid      : nsl.noc.noc_id;
    tgtid      : nsl.noc.noc_id
    );
  port(
    p_resetn    : in std_ulogic;
    p_clk       : in std_ulogic;

    p_uart_tx   : out std_ulogic;
    p_uart_rx   : in  std_ulogic;

    p_tx_val  : in  nsl.flit.flit_cmd;
    p_tx_ack  : out nsl.flit.flit_ack;

    p_rx_val : out nsl.flit.flit_cmd;
    p_rx_ack : in  nsl.flit.flit_ack
    );
end entity;

architecture hier of uart_noc_8n1 is

  signal s_framed_tx_val, s_framed_rx_val : nsl.fifo.fifo_framed_cmd;
  signal s_framed_tx_ack, s_framed_rx_ack : nsl.fifo.fifo_framed_rsp;

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
      p_data => s_framed_tx_val.data,
      p_ready => s_framed_tx_ack.ack,
      p_data_val => s_framed_tx_val.val
      );

  rx: nsl.uart.uart_8n1_rx
    generic map(
      p_clk_rate => p_clk_rate,
      baud_rate => baud_rate
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_uart_rx => p_uart_rx,
      p_data => s_framed_rx_val.data,
      p_data_val => s_framed_rx_val.val
      );

  to_noc: nsl.noc.noc_from_framed
    generic map(
      srcid => srcid,
      tgtid => tgtid,
      data_depth => 256,
      txn_depth => 1
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_in_val => s_framed_rx_val,
      p_in_ack => s_framed_rx_ack,
      p_out_val => p_rx_val,
      p_out_ack => p_rx_ack
      );
  
  from_noc: nsl.noc.noc_to_framed
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_out_val => s_framed_tx_val,
      p_out_ack => s_framed_tx_ack,
      p_in_val => p_tx_val,
      p_in_ack => p_tx_ack
      );

end;
