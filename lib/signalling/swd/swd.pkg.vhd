library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

package swd is

  type swd_bus is record
    dio : std_logic;
    clk : std_logic;
  end record;

  type swd_master_c is record
    dio : signalling.io.io_c;
    clk : std_ulogic;
  end record;

  type swd_master_s is record
    dio : signalling.io.io_s;
  end record;

  type swd_slave_c is record
    dio : signalling.io.io_c;
  end record;

  type swd_slave_s is record
    dio : signalling.io.io_s;
    clk : std_ulogic;
  end record;

end package swd;
