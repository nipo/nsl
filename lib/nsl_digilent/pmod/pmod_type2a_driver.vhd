library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_io, work;

entity pmod_type2a_driver is
  port(
    pmod_io: inout work.pmod.pmod_double_t;
    spi_i: in nsl_spi.spi.spi_master_o;
    spi_o: out nsl_spi.spi.spi_master_i;
    cs_n_i: in nsl_io.io.opendrain_vector(2 to 3);
    reset_i: in nsl_io.io.opendrain;
    int_o: out std_ulogic
    );
end entity;

architecture beh of pmod_type2a_driver is

begin

  type2_driver: work.pmod.pmod_type2_driver
    port map(
      pmod_io => pmod_io(1 to 4),
      spi_i => spi_i,
      spi_o => spi_o
      );

  int_o <= not pmod_io(5);

  reset_driver: nsl_io.io.opendrain_io_driver
    port map(
      v_i => reset_i,
      io_io => pmod_io(6)
      );
  
  cs2_driver: nsl_io.io.opendrain_io_driver
    port map(
      v_i => cs_n_i(2),
      io_io => pmod_io(7)
      );

  cs3_driver: nsl_io.io.opendrain_io_driver
    port map(
      v_i => cs_n_i(3),
      io_io => pmod_io(8)
      );

end architecture;
