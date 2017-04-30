library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.flit.all;
use nsl.noc.all;

package uart is

  component uart_noc_8n1 is
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
  end component;

  component uart_8n1_tx is
    generic(
      p_clk_rate : natural;
      baud_rate : natural
      );
    port(
      p_resetn    : in std_ulogic;
      p_clk       : in std_ulogic;

      p_uart_tx   : out std_ulogic;

      p_data      : in std_ulogic_vector(7 downto 0);
      p_ready     : out std_ulogic;
      p_data_val  : in std_ulogic
      );
  end component;

  component uart_8n1_rx is
    generic(
      p_clk_rate : natural;
      baud_rate : natural
      );
    port(
      p_resetn    : in std_ulogic;
      p_clk       : in std_ulogic;

      p_uart_rx   : in std_ulogic;

      p_data      : out std_ulogic_vector(7 downto 0);
      p_data_val  : out std_ulogic
      );
  end component;

end package uart;
