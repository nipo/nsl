library ieee;
use ieee.std_logic_1164.all;

library work;
use work.avalon_st.all;

entity avalon_st_dumper is
  generic(
    config_c : config_t;
    prefix_c : string := "AVST"
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    bus_i : in bus_t
    );
end entity;

architecture beh of avalon_st_dumper is
begin
end architecture;
