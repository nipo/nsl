library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi is

  type spi_bus is record
    mosi : std_logic;
    miso : std_logic;
    sck  : std_logic;
    cs_n : std_logic;
  end record;

  type spi_slave_i is record
    mosi : std_ulogic;
    sck  : std_ulogic;
    cs_n : std_ulogic;
  end record;

  type spi_slave_o is record
    miso : std_ulogic;
  end record;

end package spi;
