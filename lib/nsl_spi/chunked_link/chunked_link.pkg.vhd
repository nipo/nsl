library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi;

-- SPI transport for nsl_bnoc.chunked_link.
--
-- Carries the chunked_link frame and credit protocol over an SPI slave
-- interface. Compared to the JTAG transport, the byte pipe is trivial:
-- CS delimits batches, the master clocks whole bytes, so there is no
-- preamble, no start-of-frame marker and no alignment pad — byte 0 of a
-- CS window is the first protocol header in each direction.
package chunked_link is

  -- SPI mode 3 (clock idle high, MOSI sampled on rising SCK, MISO driven
  -- on falling SCK), MSB first, for interoperability with stock SPI
  -- masters.
  --
  -- The protocol layer runs in the clock_i domain; per-byte strobes are
  -- resynchronised from the SCK domain, so SCK must be slow enough for a
  -- byte to cross: SCK <= clock_i / 4. CS must stay deasserted a few
  -- clock_i cycles between windows so the transmit side restarts on a
  -- frame boundary.
  --
  -- The master must honour the advertised RX credit and TX budget rules
  -- of chunked_link, and always end a window at a frame boundary of its
  -- own transmit stream. There is no in-band reset: reset_n_i is the
  -- only hard reset of the transport.
  component spi_chunked_link_slave is
    generic(
      rx_fifo_depth_c : positive := 256;
      tx_fifo_depth_c : positive := 256
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      spi_i : in  nsl_spi.spi.spi_slave_i;
      spi_o : out nsl_spi.spi.spi_slave_o;

      -- System -> master (MISO direction).
      tx_i : in  nsl_bnoc.framed.framed_req_t;
      tx_o : out nsl_bnoc.framed.framed_ack_t;

      -- Master -> system (MOSI direction).
      rx_o : out nsl_bnoc.framed.framed_req_t;
      rx_i : in  nsl_bnoc.framed.framed_ack_t
      );
  end component;

end package;
