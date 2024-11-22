library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_simulation;
use work.axi4_mm.all;
use nsl_simulation.logging.all;

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

  dumper: process is
  begin
    wait until rising_edge(clock_i);

    if reset_n_i /= '0' then
      if is_valid(config_c, master_i.aw) and is_ready(config_c, slave_i.aw) then
        log_info(prefix_c & " AW < " & to_string(config_c, master_i.aw));
      end if;

      if is_valid(config_c, master_i.w) and is_ready(config_c, slave_i.w) then
        log_info(prefix_c & "  W < " & to_string(config_c, master_i.w));
      end if;

      if is_valid(config_c, slave_i.b) and is_ready(config_c, master_i.b) then
        log_info(prefix_c & "  B > " & to_string(config_c, slave_i.b));
      end if;

      if is_valid(config_c, master_i.ar) and is_ready(config_c, slave_i.ar) then
        log_info(prefix_c & " AR < " & to_string(config_c, master_i.ar));
      end if;
      
      if is_valid(config_c, slave_i.r) and is_ready(config_c, master_i.r) then
        log_info(prefix_c & "  R > " & to_string(config_c, slave_i.r));
      end if;
    end if;
  end process;

end architecture;
