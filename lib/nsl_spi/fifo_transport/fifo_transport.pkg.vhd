library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc;

-- Fifo transport encapsulates a bi-directinoal fifo inside a standard
-- SPI bus.
--
-- For a N-wide fifo, fifo_transport requires N+2 bits per word. For
-- every word, the two side bits tell whether each party is sending
-- meaningful data, and whether it is ready to receive data.
--
-- After the N+2 bits are exchanged, each party decides whether it
-- should interpret incoming stream, and whether it should consider
-- its data as accepted.
--
-- Master drives the SPI bus, slave accepts the SPI clock from the
-- master.
--
-- By convention, every SPI word is (in transmission order):
-- [READY] [VALID] [N data bits, MSB first]
--
-- When encapsulating framed data, SPI word is (in transmission order):
-- [READY] [VALID] [LAST] [8 data bits, MSB first]
package fifo_transport is

  -- A Fifo to SPI adapter on master side.  Uses the SPI framed
  -- controller in a way it may share the SPI bus with other unrelated
  -- slaves.
  component spi_fifo_transport_master
    generic(
      -- Fifo width, bits
      width_c : positive
      );
    port(
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      -- Whether we should send or receive data at all. If not
      -- enabled, no transaction is performed on the SPI bus.
      enable_i    : in std_ulogic := '1';

      -- SPI command stream parameters
      div_i       : in unsigned(6 downto 0);
      cpol_i      : in std_ulogic := '0';
      cpha_i      : in std_ulogic := '0';
      cs_i        : in unsigned(2 downto 0);

      -- Whether slave has some data to give us.
      irq_n_i     : in std_ulogic := '0';

      -- TX path
      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_valid_i  : in  std_ulogic;
      tx_ready_o  : out std_ulogic;

      -- RX path
      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_valid_o  : out std_ulogic;
      rx_ready_i  : in  std_ulogic;

      -- To nsl_spi.transactor.spi_framed_transactor
      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in  nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

  -- A Fifo to SPI adapter, slave side.
  --
  -- SPI bus is oversampled with clock_i.
  --
  -- Accepts pipelining of multiple words (i.e. sending/receiving of
  -- multiple 2+N bits in a single CS_n Select/Unselect frame).
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

  -- Encapsulates a Framed (8-bit + last) to SPI
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

  -- Encapsulates a Framed (8-bit + last) to SPI
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
