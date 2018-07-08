library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

entity io_io_dir_driver is
  port(
    control : in signalling.io.io_c;
    status  : out signalling.io.io_s;
    io      : inout std_logic;
    dir_out : out std_ulogic
    );
end entity;

architecture impl of io_io_dir_driver is
begin

  io <= control.v when control.en = '1' else 'Z';
  dir_out <= control.en;
  status.v <= io;
  
end architecture;
