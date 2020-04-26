library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity opendrain_io_driver is

  port(
    v_i : in nsl_io.io.opendrain;
    v_o : out std_ulogic;
    io_io : inout std_logic
    );

end entity;

architecture beh of opendrain_io_driver is
begin

  io_io <= '0' when v_i.drain_n = '0' else 'Z';
  v_o <= to_x01(io_io);
  
end architecture;
