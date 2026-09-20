library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_output_tristated is
  port(
    p_se : in nsl_io.io.tristated;
    p_diff : out diff_pair
    );
end entity;

architecture simulation of pad_diff_output_tristated is

begin

  p_diff.p <= p_se.v when p_se.en = '1' else 'Z';
  p_diff.n <= not p_se.v when p_se.en = '1' else 'Z';

end architecture;
