library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity pad_diff_io is
  port(
    v_i : in nsl_io.io.tristated;
    v_o : out std_ulogic;
    p_io : inout std_logic;
    n_io : inout std_logic
    );
end entity;

architecture simulation of pad_diff_io is

begin

  p_io <= v_i.v when v_i.en = '1' else 'Z';
  n_io <= not v_i.v when v_i.en = '1' else 'Z';
  v_o <= to_x01(p_io);

end architecture;
