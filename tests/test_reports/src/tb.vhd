library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation;

architecture sim of tb is 
begin
  test: process
  begin
    nsl_simulation.test_reports.test_suite_start("TESTING REPORT CREATION");
    nsl_simulation.test_reports.test_case_result("TEST A", true);
    nsl_simulation.test_reports.test_case_result("TEST B", false);
    nsl_simulation.test_reports.test_suite_end;
    wait;
  end process;
end architecture;
