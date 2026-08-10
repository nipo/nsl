library ieee;
use ieee.std_logic_1164.all;

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

  function resolve(c: boolean) return integer
  is
  begin
    if c then
      return 0;
    else
      return 1;
    end if;
  end function;

  signal assert_fail: std_ulogic_vector(0 to 0);

begin

  assert_fail(resolve(condition_c)) <= unused_i;
  
end architecture;
