library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity tristated_io_driver is

  port(
    v_i : in nsl_io.io.tristated;
    v_o : out std_ulogic;
    io_io : inout std_logic
    );

end entity;

architecture beh of tristated_io_driver is
begin

  io_io <= v_i.v when v_i.en = '1' else 'Z';
  v_o <= to_x01(io_io);
  
end architecture;
