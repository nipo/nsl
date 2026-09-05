library ieee;
use ieee.std_logic_1164.all;

library work;
use work.assertion.all;

entity synth_assert is
  generic(
    message_c: string;
    condition_c: boolean
    );
  port(
    unused_i : in std_ulogic
    );
end entity;

architecture beh of synth_assert is

  signal assert_fail: std_ulogic_vector(0 to 0);

begin

  assert_fail(resolve(condition_c)) <= unused_i;

end architecture;
