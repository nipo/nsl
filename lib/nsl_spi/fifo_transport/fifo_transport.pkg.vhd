library ieee;
use ieee.std_logic_1164.all;

library nsl_spi;

package fifo_transport is

  component spi_fifo_transport_master
    generic(
      width_c : positive;
      -- SPI Clock divisor from fifo clock
      divisor_c : integer range 2 to 65536
      );
    port(
      -- clocks the fifo
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      enable_i    : in  std_ulogic := '1';

      spi_o       : out nsl_spi.spi.spi_slave_i;
      spi_i       : in  nsl_spi.spi.spi_slave_o;
      irq_n_i     : in  std_ulogic;

      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_valid_i  : in  std_ulogic;
      tx_ready_o  : out std_ulogic;

      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_valid_o  : out std_ulogic;
      rx_ready_i  : in  std_ulogic
      );
  end component;

  component spi_fifo_transport_slave
    generic(
      width_c : positive
      );
    port(
      -- SPI interface is totally asynchronous to rest of the system
      spi_i       : in  nsl_spi.spi.spi_slave_i;
      spi_o       : out nsl_spi.spi.spi_slave_o;
      irq_n_o     : out std_ulogic;

      -- Clocks the fifo
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_valid_i  : in  std_ulogic;
      tx_ready_o  : out std_ulogic;

      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_valid_o  : out std_ulogic;
      rx_ready_i  : in  std_ulogic
      );
  end component;

end package fifo_transport;
