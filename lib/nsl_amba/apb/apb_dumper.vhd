library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_simulation;
use work.apb.all;
use nsl_simulation.logging.all;

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

  dumper: process is
  begin
    wait until rising_edge(clock_i);

    if reset_n_i /= '0' then
      if (is_access(config_c, bus_i.m) and is_ready(config_c, bus_i.s))
        or is_wakeup(config_c, bus_i.s) then
        log_info(prefix_c & " " & to_string(config_c, bus_i.m)
                 & " -> " & to_string(config_c, bus_i.s,
                                      hide_data => is_write(config_c, bus_i.m)));
      elsif is_selected(config_c, bus_i.m) then
        log_info(prefix_c & " "  & to_string(config_c, bus_i.m));
      end if;

    end if;
  end process;

end architecture;
