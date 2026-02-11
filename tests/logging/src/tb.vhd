library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;

entity tb is
end tb;

architecture arch of tb is
begin
  nsl_simulation.logging.log_debug("This is a debug message");
  nsl_simulation.logging.log_info("This is an info message");
  nsl_simulation.logging.log_warning("This is a warning message");
  nsl_simulation.logging.log_error("This is an error message");
  nsl_simulation.logging.log_fatal("This is a fatal message");
  nsl_simulation.control.terminate(0);
end architecture;

