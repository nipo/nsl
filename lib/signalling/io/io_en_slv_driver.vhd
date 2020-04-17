library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

entity io_en_slv_driver is
  port(
    output_i : in signalling.io.io_oe;
    input_o : out std_ulogic;
    io_io : inout std_logic
    );
end entity;

architecture impl of io_en_slv_driver is
begin

  input_o <= io_io;
  io_io <= output_i.v when output_i.en = '1' else 'Z';

end architecture;
