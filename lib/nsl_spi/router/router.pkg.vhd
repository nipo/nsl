library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi;

package router is

  component spi_router is
    generic(
      slave_count_c : positive range 1 to 255
      );
    port(
      spi_i  : in nsl_spi.spi.spi_slave_i;
      spi_o  : out nsl_spi.spi.spi_slave_o;

      sck_o  : out std_ulogic;
      cs_n_o : out std_ulogic_vector(0 to slave_count_c-1);
      mosi_o : out std_ulogic;
      miso_i : in  std_ulogic_vector(0 to slave_count_c-1)
      );
  end component;

end package router;
