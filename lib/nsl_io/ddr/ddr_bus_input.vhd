library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_bus_input is
  generic(
    invert_clock_polarity_c : boolean := false;
    ddr_width : natural
    );
  port(
    clock_i   : in  nsl_io.diff.diff_pair;
    dd_i    : in  std_ulogic_vector(ddr_width - 1 downto 0);
    d_o    : out std_ulogic_vector(2 * ddr_width - 1 downto 0)
    );
end entity;

architecture rtl of ddr_bus_input is
begin

  bus_loop: for i in dd_i'range
  generate
    o: nsl_io.ddr.ddr_input
      generic map(
        invert_clock_polarity_c => invert_clock_polarity_c
        )
      port map(
        clock_i => clock_i,
        d_o(0) => d_o(i),
        d_o(1) => d_o(i+ddr_width),
        dd_i => dd_i(i)
        );
  end generate;

end architecture;
