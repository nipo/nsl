library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc;

package slave is

  -- A generic SPI controller that acts as a memory.
  --
  -- There is one byte for opcode. Any opcode other than write one is
  -- read.
  --
  -- There is a configurable count of bytes for address, and then
  -- every byte in transaction is either one more byte read or write.
  component spi_memory_controller is
    generic(
      addr_bytes_c   : natural range 1 to 4          := 1;
      write_opcode_c : std_ulogic_vector(7 downto 0) := x"F8"
      );
    port(
      spi_i          : in nsl_spi.spi.spi_slave_i;
      spi_o          : out nsl_spi.spi.spi_slave_o;
      selected_o     : out std_ulogic;
      mem_addr_o     : out unsigned(addr_bytes_c*8-1 downto 0);
      mem_r_data_i   : in  std_ulogic_vector(7 downto 0);
      mem_r_strobe_o : out std_ulogic;
      mem_r_done_i   : in  std_ulogic := '1';
      mem_w_data_o   : out std_ulogic_vector(7 downto 0);
      mem_w_strobe_o : out std_ulogic;
      mem_w_done_i   : in  std_ulogic := '1'
      );
  end component;

  constant SPI_FRAMED_GW_STATUS      : nsl_bnoc.framed.framed_data_t := "0-------";
  constant SPI_FRAMED_GW_ST_OUT_RDY  : nsl_bnoc.framed.framed_data_t := "------1-";
  constant SPI_FRAMED_GW_ST_IN_VALID : nsl_bnoc.framed.framed_data_t := "-------1";
  constant SPI_FRAMED_GW_PUT         : nsl_bnoc.framed.framed_data_t := "10------";
  constant SPI_FRAMED_GW_GET         : nsl_bnoc.framed.framed_data_t := "11-----0";
  constant SPI_FRAMED_GW_GET_CONT    : nsl_bnoc.framed.framed_data_t := "11-----1";

  -- A SPI slave that allows to talk to a pair of framed pipes.
  component spi_framed_gateway
    generic(
      msb_first_c   : boolean := true
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      spi_i : in  nsl_spi.spi.spi_slave_i;
      spi_o : out nsl_spi.spi.spi_slave_o;

      outbound_o  : out nsl_bnoc.framed.framed_req;
      outbound_i  : in  nsl_bnoc.framed.framed_ack;
      inbound_i  : in  nsl_bnoc.framed.framed_req;
      inbound_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package slave;
