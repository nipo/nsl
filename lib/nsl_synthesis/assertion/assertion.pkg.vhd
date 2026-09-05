library ieee;
use ieee.std_logic_1164.all;

package assertion is

  function resolve(c: boolean) return integer;

  -- Fails elaboration with the message when the condition does not
  -- hold; elaborates to nothing otherwise.  Instantiable, so
  -- generated code can drop it in an instantiation list.
  component synth_assert is
    generic(
      message_c : string;
      condition_c : boolean
      );
    port(
      unused_i : in std_ulogic
      );
  end component;

  -- Variant with a procedure
  procedure synth_assert_proc(
    constant condition_c : in boolean;
    constant msg_c: in string);

end package;

package body assertion is

  function resolve(c: boolean) return integer
  is
  begin
    if c then
      return 0;
    else
      return 1;
    end if;
  end function;

  procedure synth_assert_proc(
    constant condition_c : in boolean;
    constant msg_c: in string)
  is
    variable assert_fail: std_ulogic_vector(0 to 0);
  begin
    assert condition_c
      report msg_c
      severity failure;

    assert_fail(resolve(condition_c)) := '-';
  end procedure;

end package body;
