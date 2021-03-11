library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package jtag is

  type jtag_bus is record
    -- Should be pulled up
    tdi  : std_logic;
    -- TAP reset, active low per IEEE1149.1
    -- Should be pulled up for normal operation
    trst : std_logic;
    -- Default level is not clearly specified, but usually 0
    tck  : std_logic;
    tdo  : std_logic;
    -- Should be pulled up
    tms  : std_logic;
  end record;

  type jtag_ate_o is record
    trst : std_ulogic;
    tdi  : std_ulogic;
    tck  : std_ulogic;
    tms  : std_ulogic;
  end record;

  constant jtag_ate_o_default : jtag_ate_o := ('0','1', '0', '1');
  
  type jtag_ate_i is record
    tdo : std_ulogic;
    rtck: std_ulogic;
  end record;

end package jtag;
