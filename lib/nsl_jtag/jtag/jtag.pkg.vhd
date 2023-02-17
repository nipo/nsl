library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.io.tristated_z;

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
    trst : nsl_io.io.tristated;
    tdi  : nsl_io.io.tristated;
    tck  : nsl_io.io.tristated;
    tms  : nsl_io.io.tristated;
  end record;

  constant jtag_ate_o_default : jtag_ate_o := (tristated_z, tristated_z, tristated_z, tristated_z);
  
  type jtag_ate_i is record
    tdo : std_ulogic;
    rtck: std_ulogic;
  end record;

  component jtag_ate_pin_driver is
    generic(
      use_rtck_c: boolean := false
      );
    port(
      enable_i: in std_ulogic := '1';

      ate_i: in jtag_ate_o;
      ate_o: out jtag_ate_i;

      trst_io: inout std_logic;
      tdi_io: inout std_logic;
      tck_io: inout std_logic;
      tms_io: inout std_logic;
      tdo_i: in std_logic;
      rtck_i: in std_logic := '0'
      );
  end component;
  
end package jtag;
