library ieee;
use ieee.std_logic_1164.all;

library work;

entity output_bus_delay_fixed is
  generic(
    width_c : natural;
    delay_ps_c: integer;
    is_ddr_c: boolean := true
    );
  port(
    data_i : in std_ulogic_vector(0 to width_c);
    data_o : out std_ulogic_vector(0 to width_c)
    );
end entity;

architecture beh of output_bus_delay_fixed is

begin

  iter: for i in data_i'range
  generate
    impl: work.delay.output_delay_fixed
      generic map(
        delay_ps_c => delay_ps_c,
        is_ddr_c => is_ddr_c
        )
      port map(
        data_i => data_i(i),
        data_o => data_o(i)
        );
  end generate;

end architecture;
