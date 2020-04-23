library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity clock_input_diff_to_diff is
  generic(
    diff_term : boolean := true;
    invert    : boolean := false
    );
  port(
    pad_i : in  nsl_io.diff.diff_pair;
    clock_o : out nsl_io.diff.diff_pair
    );
end entity;

architecture gen of clock_input_diff_to_diff is

begin

  inv: if invert
  generate
    clock_o.n <= pad_i.p;
    clock_o.p <= pad_i.n;
  end generate;

  noinv: if not invert
  generate
    clock_o.p <= pad_i.p;
    clock_o.n <= pad_i.n;
  end generate;

end architecture;
