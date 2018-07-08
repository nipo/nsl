library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

entity od_std_logic_driver is
  generic(
    hi_z : boolean := true
    );
  port(
    control : in signalling.io.od_c;
    status : out signalling.io.od_s;
    io : inout std_logic
    );
end entity;

architecture impl of od_std_logic_driver is
begin

  status.v <= io;

  driver: process (control)
  begin
    if hi_z then
      io <= 'Z';
    else
      io <= 'H';
    end if;

    if control.drain = '1' then
      io <= '0';
    end if;
  end process;

end architecture;
