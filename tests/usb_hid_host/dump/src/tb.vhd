library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_simulation;
use nsl_data.text.all;
use nsl_usb.ukp.all;
use nsl_usb.hid_program.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;

-- Listing for correlating the host's program_counter diagnostic with
-- instructions and symbolic branch labels.
entity tb is
end entity;

architecture arch of tb is
  constant prog_c: program_t := hid_program(hid_program_config_t'(
    poll_interval_ms => 8, report_length => 7,
    configuration_value => 1, debounce_ms => 200));
  constant rom_c: rom_t := assemble(prog_c);
begin
  main: process is
    variable addr: natural := 0;
  begin
    for i in prog_c'range loop
      if prog_c(i).opcode = UKP_LABEL then
        log_info("     label " & to_string(prog_c(i).operand)
                 & " -> " & to_hex_string(std_ulogic_vector(to_unsigned(addr, 12))));
      else
        log_info(to_hex_string(std_ulogic_vector(to_unsigned(addr, 12)))
                 & ": " & to_hex_string(rom_c(addr)) & " " & to_string(prog_c(i)));
        addr := addr + 1;
      end if;
    end loop;
    log_info("total " & to_string(addr));
    terminate(0);
  end process;
end architecture;
