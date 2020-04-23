library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package swd is

  type swd_master_o is record
    dio : nsl_io.io.directed;
    clk : std_ulogic;
  end record;

  type swd_master_i is record
    dio : std_ulogic;
  end record;

  type swd_master_bus is
  record
    o: swd_master_o;
    i: swd_master_i;
  end record;
  
  type swd_slave_o is record
    dio : nsl_io.io.directed;
  end record;

  type swd_slave_i is record
    clk : std_ulogic;
    dio : std_ulogic;
  end record;

  type swd_slave_bus is
  record
    o: swd_slave_o;
    i: swd_slave_i;
  end record;
    
end package swd;
