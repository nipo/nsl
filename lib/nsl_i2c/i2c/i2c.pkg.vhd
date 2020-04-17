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
    scl : std_ulogic;
    sda : std_ulogic;
  end record;

  type i2c_o is record
    scl : signalling.io.od_c;
    sda : signalling.io.od_c;
  end record;

  type i2c_i_vector is array(natural range <>) of i2c_i;
  type i2c_o_vector is array(natural range <>) of i2c_o;
  
  component i2c_line_driver is
    port(
      bus_io : inout i2c_bus;
      bus_o : out i2c_i;
      bus_i : in i2c_o
      );
  end component;

  component i2c_resolver is
    generic(
      port_count : natural
      );
    port(
      bus_i : in i2c_o_vector(0 to port_count-1);
      bus_o : out i2c_i
      );
  end component;

end package i2c;
