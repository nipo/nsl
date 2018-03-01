library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package swd is

  type swd_bus is record
    dio : std_logic;
    clk : std_logic;
  end record;

  type swd_o is record
    dio_oe : std_ulogic;
    dio : std_ulogic;
    clk : std_ulogic;
  end record;

  type swd_i is record
    dio : std_ulogic;
  end record;

end package swd;
