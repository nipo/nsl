library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.apb.all;

entity apb_dumper is
  generic(
    config_c : config_t;
    prefix_c : string := "APB"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    bus_i : in bus_t
    );
end entity;

architecture beh of apb_dumper is
begin
end architecture;
