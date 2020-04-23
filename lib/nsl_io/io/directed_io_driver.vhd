library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity directed_io_driver is

  port(
    v_i : in nsl_io.io.directed;
    v_o : out std_ulogic;
    io_io : inout std_logic
    );

end entity;

architecture beh of directed_io_driver is
begin

  io_io <= v_i.v when v_i.output = '1' else 'Z';
  v_o <= to_x01(io_io) when v_i.output = '0' else '-';
  
end architecture;
