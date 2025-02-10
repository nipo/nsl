library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_data.text.all;

entity tb is
  generic (
    integer_c: integer := 0;
    string_c: string := "lol"
    );
end tb;

architecture arch of tb is

begin

  test: process is
  begin
    log_info("integer", to_string(integer_c));
    log_info("string", string_c);

    assert_equal("integer", integer_c, 42, failure);
    assert_equal("string", string_c, "hello", failure);
    wait;
  end process;
    
end;
