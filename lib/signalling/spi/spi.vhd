library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi is

  type spi_bus is record
    mosi : std_logic;
    miso : std_logic;
    sck  : std_logic;
    cs   : std_logic;
  end record;

end package spi;
