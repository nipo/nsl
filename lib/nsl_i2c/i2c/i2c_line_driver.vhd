library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling, nsl_i2c;

entity i2c_line_driver is
  port(
    bus_io : inout nsl_i2c.i2c.i2c_bus;
    bus_o : out nsl_i2c.i2c.i2c_i;
    bus_i : in nsl_i2c.i2c.i2c_o
    );
end entity;

architecture beh of i2c_line_driver is
begin

  sda_driver: signalling.io.od_std_logic_driver
    port map(
      control => bus_i.sda,
      status.v => bus_o.sda,
      io => bus_io.sda
      );

  scl_driver: signalling.io.od_std_logic_driver
    port map(
      control => bus_i.scl,
      status.v => bus_o.scl,
      io => bus_io.scl
      );

end architecture;
