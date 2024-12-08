library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.axi4_mm.all;

entity axi4_mm_dumper is
  generic(
    config_c : config_t;
    prefix_c : string := "AXI4MM"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    master_i : in master_t;
    slave_i : in slave_t
    );
end entity;

architecture beh of axi4_mm_dumper is

begin

end architecture;
