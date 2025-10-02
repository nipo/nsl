library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

library unisim;

entity pad_tmds_output is
  generic(
    invert_c : boolean := false;
    driver_mode_c : string := "default"
    );
  port(
    data_i : in std_ulogic;
    pad_o : out diff_pair
    );
end entity;

architecture rtl of pad_tmds_output is

  signal data_s : std_ulogic;
  
begin

  data_s <= (not data_i) when invert_c else data_i;
  
  se2diff: unisim.vcomponents.obufds
    generic map(
      iostandard => "TMDS_33"
      )
    port map(
      o => pad_o.p,
      ob => pad_o.n,
      i => data_s
      );
  
end architecture;
