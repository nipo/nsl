library ieee;
use ieee.std_logic_1164.all;

library nsl_i2c, nsl_io, work;

entity pmod_type6_driver is
  port(
    pmod_io: inout work.pmod.pmod_single_t;
    i2c_i: in nsl_i2c.i2c.i2c_o;
    i2c_o: out nsl_i2c.i2c.i2c_i;
    reset_i: in nsl_io.io.opendrain;
    int_o: out std_ulogic
    );
end entity;

architecture beh of pmod_type6_driver is

begin

  driver: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.scl => pmod_io(3),
      bus_io.sda => pmod_io(4),
      bus_o => i2c_o,
      bus_i => i2c_i
      );

  int_o <= not pmod_io(1);

  reset_driver: nsl_io.io.opendrain_io_driver
    port map(
      v_i => reset_i,
      io_io => pmod_io(2)
      );

end architecture;
