library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent;

entity pmod_btn_4_4_input is
  port(
    pmod_io : inout nsl_digilent.pmod.pmod_double_t;

    s_o : out std_ulogic_vector(1 to 4);
    k_o : out std_ulogic_vector(1 to 4)
    );
end entity;

architecture beh of pmod_btn_4_4_input is

begin

  s_o(1) <= not pmod_io(8);
  s_o(2) <= not pmod_io(7);
  s_o(3) <= not pmod_io(2);
  s_o(4) <= not pmod_io(1);
  k_o(1) <= not pmod_io(4);
  k_o(2) <= not pmod_io(3);
  k_o(3) <= not pmod_io(6);
  k_o(4) <= not pmod_io(5);
  
end architecture;
  
