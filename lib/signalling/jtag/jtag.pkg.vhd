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

  type jtag_ate_o is record
    trst : std_ulogic;
    tdi : std_ulogic;
    tck : std_ulogic;
    tms : std_ulogic;
  end record;

  type jtag_ate_i is record
    tdo: std_ulogic;
    rtck: std_ulogic;
  end record;

end package jtag;
