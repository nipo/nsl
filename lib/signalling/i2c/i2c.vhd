library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

package i2c is

  type i2c_bus is record
    scl : std_logic;
    sda : std_logic;
  end record;

  type i2c_i is record
    scl : signalling.io.single;
    sda : signalling.io.single;
  end record;

  type i2c_o is record
    scl : signalling.io.od_c;
    sda : signalling.io.od_c;
  end record;

end package i2c;
