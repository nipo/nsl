library ieee;
use ieee.std_logic_1164.all;

library work, nsl_data;
use work.axi4_stream.all;
use nsl_data.text.all;

entity axi4_stream_dumper is
  generic(
    config_c : config_t;
    prefix_c : string := "AXIS"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    bus_i : in bus_t
    );
end entity;

architecture beh of axi4_stream_dumper is
  
begin

end architecture;
