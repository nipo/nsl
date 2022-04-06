library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_tmds_input is
  generic(
    invert_c : boolean := false
    );
  port(
    data_o : out std_ulogic;
    pad_i : in diff_pair
    );
end entity;

architecture sim of pad_tmds_input is

  signal data_s: std_ulogic;
  
begin

  data_s <= pad_i.p and not pad_i.n;
  data_o <= (not data_s) when invert_c else data_s;

end architecture;
