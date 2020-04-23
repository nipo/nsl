library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package stream is

  type axis_16l_ms is
  record
    tdata  : std_ulogic_vector (15 downto 0);
    tvalid : std_ulogic;
    tlast  : std_ulogic;
  end record;

  type axis_16l_sm is
  record
    tready : std_ulogic;
  end record;

  type axis_16l_sm_vector is array(natural range <>) of axis_16l_sm;
  type axis_16l_ms_vector is array(natural range <>) of axis_16l_ms;

  type axis_16l is
  record
    m2s: axis_16l_ms;
    s2m: axis_16l_sm;
  end record;

  type axis_16l_vector is array(natural range <>) of axis_16l;

end package axis;
