library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

-- I2C bus and IOs abstraction datatypes.
package i2c is

  -- An I2C bus representation. Uses resolution from the underlying
  -- std_logic.
  type i2c_bus is record
    scl : std_logic;
    sda : std_logic;
  end record;

  -- An input to a I2C device (only senses the bus).
  type i2c_i is record
    scl : std_ulogic;
    sda : std_ulogic;
  end record;

  -- An output from an I2C device. May only drive bus lines down.
  type i2c_o is record
    scl : nsl_io.io.opendrain;
    sda : nsl_io.io.opendrain;
  end record;

  -- Helper that internally merges two I2C drivers as one.
  function "+"(a, b : i2c_o) return i2c_o;
  
  type i2c_i_vector is array(natural range <>) of i2c_i;
  type i2c_o_vector is array(natural range <>) of i2c_o;

  -- Drives an I2C bus from differentiated IO types.
  component i2c_line_driver is
    port(
      bus_io : inout i2c_bus;
      bus_o : out i2c_i;
      bus_i : in i2c_o
      );
  end component;

  -- Resolves multiple drivers as one I2C bus state. Mostly suitable for
  -- simulation of I2C physical bus.
  component i2c_resolver is
    generic(
      port_count : natural
      );
    port(
      bus_i : in i2c_o_vector(0 to port_count-1);
      bus_o : out i2c_i
      );
  end component;

  -- Monitors I2C lines and identifies start, stop conditions.  Also
  -- acts as a line filter
  component i2c_line_monitor is
    generic(
      debounce_count_c : integer
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;
      raw_i : in i2c_i;
      filtered_o : out i2c_i;
      start_o : out std_ulogic;
      stop_o : out std_ulogic
      );
  end component;

end package i2c;

package body i2c is

  use nsl_io.io."+";

  function "+"(a, b : i2c_o) return i2c_o is
    variable ret : i2c_o;
  begin
    ret.scl := a.scl + b.scl;
    ret.sda := a.sda + b.sda;
    return ret;
  end function;

end package body i2c;
