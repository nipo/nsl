library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_transceiver_clock_input is
  port(
    p_diff : in diff_pair;
    p_se : out std_ulogic
    );
end entity;

architecture sim of pad_diff_transceiver_clock_input is

begin

  p_se <= p_diff.p;

end architecture;
