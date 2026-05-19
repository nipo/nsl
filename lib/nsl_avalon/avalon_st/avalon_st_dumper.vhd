library ieee;
use ieee.std_logic_1164.all;

library work, nsl_data, nsl_simulation;
use work.avalon_st.all;
use nsl_simulation.logging.all;
use nsl_data.text.all;

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

  d: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      null;
    elsif rising_edge(clock_i) then
      if is_ready(config_c, bus_i.snk) and is_valid(config_c, bus_i.src) then
        log_info(prefix_c & " - " & to_string(config_c, bus_i.src));
      end if;
    end if;
  end process;

end architecture;
