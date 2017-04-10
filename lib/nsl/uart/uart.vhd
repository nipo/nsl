library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package uart is

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

end package uart;
