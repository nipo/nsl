library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

package slave is

  -- A generic SPI controller that acts as a memory.
  --
  -- There is one byte for opcode. Any opcode other than write one is
  -- read.
  --
  -- There is a configurable count of bytes for address, used as big-endian.
  -- Data words are transceived in order.
  component spi_memory_controller is
    generic(
      addr_bytes_c   : natural range 1 to 4 := 1;
      data_bytes_c   : natural range 1 to 4 := 1;
      write_opcode_c : byte := x"0b"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      spi_i          : in nsl_spi.spi.spi_slave_i;
      spi_o          : out nsl_spi.spi.spi_slave_o;
    
      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';

      selected_o     : out std_ulogic;

      addr_o  : out unsigned(addr_bytes_c*8-1 downto 0);

      rdata_i  : in  byte_string(0 to data_bytes_c-1);
      rready_o : out std_ulogic;
      rvalid_i : in  std_ulogic := '1';

      wdata_o  : out byte_string(0 to data_bytes_c-1);
      wvalid_o : out std_ulogic;
      wready_i : in  std_ulogic := '1'
      );
  end component;

  constant SPI_FRAMED_GW_STATUS      : nsl_bnoc.framed.framed_data_t := "00------";
  constant SPI_FRAMED_GW_ST_OUT_RDY  : nsl_bnoc.framed.framed_data_t := "------1-";
  constant SPI_FRAMED_GW_ST_IN_VALID : nsl_bnoc.framed.framed_data_t := "-------1";
  constant SPI_FRAMED_GW_PUT         : nsl_bnoc.framed.framed_data_t := "10------";
  constant SPI_FRAMED_GW_GET         : nsl_bnoc.framed.framed_data_t := "11------";

  -- A SPI slave that allows to talk to a pair of framed pipes.
  component spi_framed_gateway
    generic(
      msb_first_c   : boolean := true;
      max_txn_length_c : positive := 128
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      spi_i : in  nsl_spi.spi.spi_slave_i;
      spi_o : out nsl_spi.spi.spi_slave_o;
    
      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';

      outbound_o  : out nsl_bnoc.framed.framed_req;
      outbound_i  : in  nsl_bnoc.framed.framed_ack;
      inbound_i  : in  nsl_bnoc.framed.framed_req;
      inbound_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package slave;
