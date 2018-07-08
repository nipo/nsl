library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

entity io_std_logic_driver is
  generic(
    hi_z : boolean := true
    );
  port(
    control : in signalling.io.io_c;
    status : out signalling.io.io_s;
    io : inout std_logic
    );
end entity;

architecture impl of io_std_logic_driver is
begin

  status.v <= io;
  io <= control.v when control.en = '1' else 'Z';

end architecture;
