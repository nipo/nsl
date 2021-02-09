library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_usb;

entity usb_io_driver is
  port(
    bus_o : out nsl_usb.usb.usb_io_s; 
    bus_i : in nsl_usb.usb.usb_io_c;
    bus_io : inout nsl_usb.usb.usb_lines
    );
end entity;

architecture beh of usb_io_driver is

begin

  dp: nsl_io.io.tristated_io_driver
    port map(
      v_i.v => bus_i.p,
      v_i.en => bus_i.oe,
      v_o => bus_o.p,
      io_io => bus_io.p
      );

  dn: nsl_io.io.tristated_io_driver
    port map(
      v_i.v => bus_i.n,
      v_i.en => bus_i.oe,
      v_o => bus_o.n,
      io_io => bus_io.n
      );
  
end architecture;
