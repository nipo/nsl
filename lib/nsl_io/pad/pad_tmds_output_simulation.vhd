library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

library unisim;

entity pad_tmds_output is
  generic(
    invert_c : boolean := false
    );
  port(
    data_i : in std_ulogic;
    pad_o : out diff_pair
    );
end entity;

architecture sim of pad_tmds_output is

  signal data_s : std_ulogic;
  
begin

  data_s <= (not data_i) when invert_c else data_i;
  pad_o <= to_diff(data_s);
  
end architecture;
