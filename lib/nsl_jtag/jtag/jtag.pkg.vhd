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
    trst : std_ulogic;
    tdi  : nsl_io.io.tristated;
    tck  : std_ulogic;
    tms  : std_ulogic;
  end record;

  constant jtag_ate_o_default : jtag_ate_o := ('1', tristated_z, '0', '1');
  
  type jtag_ate_i is record
    tdo : std_ulogic;
    rtck: std_ulogic;
  end record;

  type jtag_tap_o is
  record
    tdo  : nsl_io.io.tristated;
    rtck : std_ulogic;
  end record;

  constant jtag_tap_o_default : jtag_tap_o := (tristated_z, '0');
  
  type jtag_tap_i is record
    tck  : std_ulogic;
    tms  : std_ulogic;
    tdi  : std_ulogic;
    trst : std_ulogic;
  end record;

  constant jtag_tap_i_default : jtag_tap_i := ('0', '1', '1', '1');

  function to_ate(s: jtag_tap_o) return jtag_ate_i;
  function to_tap(s: jtag_ate_o) return jtag_tap_i;
  
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

package body jtag is

  function to_ate(s: jtag_tap_o) return jtag_ate_i is
  begin
    return (
      tdo => s.tdo.v,
      rtck => s.rtck
      );
  end function;
  
  function to_tap(s: jtag_ate_o) return jtag_tap_i is
  begin
    return (
      trst => s.trst,
      tms => s.tms,
      tck => s.tck,
      tdi => s.tdi.v
      );
  end function;

end package body;
  
