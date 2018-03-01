library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jtag is

  type jtag_bus is record
    tdi : std_logic;
    tck : std_logic;
    tdo : std_logic;
    tms : std_logic;
  end record;

end package jtag;
