library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_io, work;

entity pmod_type2_driver is
  port(
    pmod_io: inout work.pmod.pmod_single_t;
    spi_i: in nsl_spi.spi.spi_master_o;
    spi_o: out nsl_spi.spi.spi_master_i
    );
end entity;

architecture beh of pmod_type2_driver is

begin

  csn_driver: nsl_io.io.opendrain_io_driver
    port map(
      v_i => spi_i.cs_n,
      io_io => pmod_io(1)
      );

  mosi_driver: nsl_io.io.tristated_io_driver
    port map(
      v_i => spi_i.mosi,
      io_io => pmod_io(2)
      );

  spi_o.miso <= pmod_io(3);
  pmod_io(4) <= spi_i.sck;

end architecture;
