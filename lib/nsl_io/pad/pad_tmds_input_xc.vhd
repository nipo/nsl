library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

library unisim;

entity pad_tmds_input is
  generic(
    invert_c : boolean := false
    );
  port(
    data_o : out std_ulogic;
    pad_i : in diff_pair
    );
end entity;

architecture rtl of pad_tmds_input is

  signal data_s: std_ulogic;
  
begin

  se2diff: unisim.vcomponents.ibufds
    generic map(
      diff_term => false,
      iostandard => "TMDS_33"
      )
    port map(
      o => data_s,
      i => pad_i.p,
      ib => pad_i.n
      );
  
  data_o <= (not data_s) when invert_c else data_s;

end architecture;
