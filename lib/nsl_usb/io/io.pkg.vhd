library ieee;
use ieee.std_logic_1164.all;

package io is

  type usb_io_c is
  record
    dp, dm, oe : std_ulogic;
    dp_pullup_en : std_ulogic;
  end record;

  type usb_io_s is
  record
    dp, dm : std_ulogic;
  end record;

  type usb_io is
  record
    dp, dm : std_logic;
  end record;

  component io_fs_driver is
    generic(
      dp_pullup_active_c : std_logic := '1';
      dp_pullup_inactive_c : std_logic := 'Z'
      );
    port(
      bus_o : out usb_io_s; 
      bus_i : in usb_io_c;
      bus_io : inout usb_io;
      dp_pullup_control_io : inout std_logic
      );
  end component;

end package;
