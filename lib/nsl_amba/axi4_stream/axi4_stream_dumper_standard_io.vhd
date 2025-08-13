library ieee;
use ieee.std_logic_1164.all;

library work, nsl_data, nsl_simulation;
use work.axi4_stream.all;
use nsl_simulation.logging.all;
use nsl_data.text.all;

entity axi4_stream_dumper_standard_io is
  generic(
    config_c : config_t;
    prefix_c : string := "AXIS"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of axi4_stream_dumper_standard_io is
  
begin

  d: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      null;
    elsif rising_edge(clock_i) then
      if is_ready(config_c, out_i) and is_valid(config_c, in_i) then
        log_info(prefix_c & " - " & to_string(config_c, in_i));
      end if;
    end if;
  end process;        

end architecture;
