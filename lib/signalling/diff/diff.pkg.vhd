library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package diff is

  type diff_pair is record
    p : std_ulogic;
    n : std_ulogic;
  end record;

  type diff_pair_vector is array(natural range <>) of diff_pair;

end package diff;
