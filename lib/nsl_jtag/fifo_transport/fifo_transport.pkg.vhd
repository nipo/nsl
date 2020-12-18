library ieee;
use ieee.std_logic_1164.all;

library nsl_jtag;

package fifo_transport is

  component jtag_fifo_transport_slave
    generic(
      width_c : positive;
      data_reg_no_c : integer;
      -- if < 0, status register is disabled
      status_reg_no_c : integer := -1;
      -- RX path is critical if we want to speculatively send data.
      -- If depth is only one, a simple cross-region slice is used instead
      rx_fifo_depth_c : positive := 1;
      -- If depth is only one, a simple cross-region slice is used instead
      tx_fifo_depth_c : positive := 1
      );
    port(
      -- Clocks the fifo, asynchronous to TCK of user reg
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;
      reset_n_o   : out std_ulogic;

      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_valid_i  : in  std_ulogic;
      tx_ready_o  : out std_ulogic;

      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_valid_o  : out std_ulogic;
      rx_ready_i  : in  std_ulogic
      );
  end component;

end package fifo_transport;
