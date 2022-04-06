library ieee;
use ieee.std_logic_1164.all;

library gowin;

entity output_delay_fixed is
  generic(
    delay_ps_c: integer
    );
  port(
    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture gowin of output_delay_fixed is

  constant tap_delay_ps_c : integer := 30;
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: gowin.components.iodelay
      generic map(
        c_static_dly => tap_count_i
        )
      port map(
        di => data_i,
        sdtap => '0',
        setn => '0',
        value => '0',
        df => open,
        do => data_o
        );
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;
  
end architecture;
