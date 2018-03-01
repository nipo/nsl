library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package i2c is

  type i2c_bus is record
    scl : std_logic;
    sda : std_logic;
  end record;

end package i2c;
