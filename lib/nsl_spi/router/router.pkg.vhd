library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_io, nsl_data;

package router is

  -- A one-to-many SPI router where first word of transaction tells
  -- what output is used.
  --
  -- CS_n is asserted on output side before the second word.
  component spi_router is
    generic(
      slave_count_c : positive range 1 to 255
      );
    port(
      spi_i  : in nsl_spi.spi.spi_slave_i;
      spi_o  : out nsl_spi.spi.spi_slave_o;

      sck_o  : out std_ulogic;
      cs_n_o : out nsl_io.io.opendrain_vector(0 to slave_count_c-1);
      mosi_o : out nsl_io.io.tristated;
      miso_i : in  std_ulogic_vector(0 to slave_count_c-1)
      );
  end component;

  -- A one-to-many SPI router where first word of transaction tells
  -- what output is used, address byte is taken from generics.
  --
  -- This block uses resampling and needs a reference clock at least 4
  -- times faster than SCK.
  --
  -- CS_n is asserted on output side before the second word.
  component spi_demux is
    generic(
      sub_address_c : nsl_data.bytestream.byte_string
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      slave_i  : in nsl_spi.spi.spi_slave_i;
      slave_o  : out nsl_spi.spi.spi_slave_o;

      master_o  : out nsl_spi.spi.spi_master_o_vector(0 to sub_address_c'length-1);
      master_i  : in nsl_spi.spi.spi_master_i_vector(0 to sub_address_c'length-1)
      );
  end component;

end package router;
