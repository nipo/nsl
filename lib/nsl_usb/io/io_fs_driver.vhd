library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_usb;

entity io_fs_driver is
  generic(
    dp_pullup_active_c : std_logic := '1';
    dp_pullup_inactive_c : std_logic := 'Z'
    );
  port(
    bus_o : out nsl_usb.io.usb_io_s; 
    bus_i : in nsl_usb.io.usb_io_c;
    bus_io : inout nsl_usb.io.usb_io;
    dp_pullup_control_io : inout std_logic
    );
end entity;

architecture beh of io_fs_driver is

  signal dp, dm : std_ulogic;
  
begin

  bus_o.dp <= to_x01(dp);
  bus_o.dm <= to_x01(dm);
  
  dp_driver: nsl_io.io.tristated_io_driver
    port map(
      v_i.v => bus_i.dp,
      v_i.en => bus_i.oe,
      v_o => dp,
      io_io => bus_io.dp
      );

  dm_driver: nsl_io.io.tristated_io_driver
    port map(
      v_i.v => bus_i.dm,
      v_i.en => bus_i.oe,
      v_o => dm,
      io_io => bus_io.dm
      );
  
  dp_pullup_control_io <= dp_pullup_active_c when bus_i.dp_pullup_en = '1' else dp_pullup_inactive_c;

end architecture;
