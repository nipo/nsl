library ieee;
use ieee.std_logic_1164.all;

-- Quartus owns the clock networks of an Altera part: the fitter assigns
-- them itself, from the fanout of every net it finds driving a clock
-- port, and a dedicated clock pin reaches a global network that way
-- without anything in the netlist asking for it.
--
-- There is no user-instantiable global buffer to put here either.  The
-- family atoms carry a clock control block, but it is per-family
-- (cyclone10lp_clkctrl and its siblings) and exists to select and gate
-- clocks rather than to force a promotion; the family-independent
-- wrapper over them, altclkctrl, is an IP-catalog megafunction with no
-- component declaration in the simulation libraries, so it is not
-- reachable from a plain VHDL source list.
--
-- A design that needs a promotion the fitter did not make asks for it
-- where the fitter reads its instructions, with a
--   set_instance_assignment -name GLOBAL_SIGNAL "GLOBAL CLOCK"
-- in the project settings, and not with a cell.
entity clock_buffer is
  generic(
    mode_c : string := "global"
    );
  port(
    clock_i : in std_ulogic;
    clock_o : out std_ulogic
    );
end entity;

architecture altera of clock_buffer is

begin

  clock_o <= clock_i;

end architecture;
