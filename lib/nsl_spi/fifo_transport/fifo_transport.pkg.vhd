library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc;

package fifo_transport is

  component spi_fifo_transport_master
    generic(
      width_c : positive
      );
    port(
      -- clocks the fifo
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      enable_i    : in std_ulogic := '1';
      div_i       : in unsigned(6 downto 0);
      cpol_i      : in std_ulogic := '0';
      cpha_i      : in std_ulogic := '0';
      cs_i        : in unsigned(2 downto 0);

      irq_n_i     : in std_ulogic := '0';

      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_valid_i  : in  std_ulogic;
      tx_ready_o  : out std_ulogic;

      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_valid_o  : out std_ulogic;
      rx_ready_i  : in  std_ulogic;

      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in  nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

  component spi_fifo_transport_slave
    generic(
      width_c : positive;
      cs_n_active_c : std_ulogic := '0'
      );
    port(
      -- Clocks the fifo and the SPI slave
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      spi_i       : in  nsl_spi.spi.spi_slave_i;
      spi_o       : out nsl_spi.spi.spi_slave_o;
      irq_n_o     : out std_ulogic;

      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';

      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_valid_i  : in  std_ulogic;
      tx_ready_o  : out std_ulogic;

      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_valid_o  : out std_ulogic;
      rx_ready_i  : in  std_ulogic
      );
  end component;

  component spi_framed_transport_master is
    port(
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      enable_i    : in std_ulogic := '1';
      div_i       : in unsigned(6 downto 0);
      cpol_i      : in std_ulogic := '0';
      cpha_i      : in std_ulogic := '0';
      cs_i        : in unsigned(2 downto 0);

      irq_n_i     : in std_ulogic := '0';

      tx_i : in  nsl_bnoc.framed.framed_req;
      tx_o : out nsl_bnoc.framed.framed_ack;
      rx_o : out nsl_bnoc.framed.framed_req;
      rx_i : in  nsl_bnoc.framed.framed_ack;

      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in  nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

  component spi_framed_transport_slave is
    generic(
      cs_n_active_c : std_ulogic := '0'
      );
    port(
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      spi_i       : in  nsl_spi.spi.spi_slave_i;
      spi_o       : out nsl_spi.spi.spi_slave_o;
      irq_n_o     : out std_ulogic;

      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';

      tx_i : in  nsl_bnoc.framed.framed_req;
      tx_o : out nsl_bnoc.framed.framed_ack;
      rx_o : out nsl_bnoc.framed.framed_req;
      rx_i : in  nsl_bnoc.framed.framed_ack
      );
  end component;

end package fifo_transport;
