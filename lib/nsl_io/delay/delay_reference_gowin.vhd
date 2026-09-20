library ieee;
use ieee.std_logic_1164.all;

entity delay_reference is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ready_o : out std_ulogic
    );
end entity;

-- A Gowin delay line is a chain of taps of a length the family states,
-- with nothing to calibrate it against: IODELAY takes its tap as a
-- number and applies it, and there is no block beside it to lock to a
-- reference the way IDELAYCTRL does.  So this carries no logic and no
-- clock of its own, and says ready as soon as it is out of reset: a
-- design that waits on it waits for nothing, which is the right answer
-- here rather than a knob that never rises.
architecture gowin of delay_reference is

begin

  ready_o <= reset_n_i;

end architecture;
