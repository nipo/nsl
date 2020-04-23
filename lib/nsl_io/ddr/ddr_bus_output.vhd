library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_bus_output is
  generic(
    ddr_width : natural
    );
  port(
    clock_i   : in  nsl_io.diff.diff_pair;
    d_i     : in  std_ulogic_vector(2 * ddr_width - 1 downto 0);
    dd_o    : out std_ulogic_vector(ddr_width - 1 downto 0)
    );
end entity;

architecture rtl of ddr_bus_output is
begin

  bus_loop: for i in dd_o'range
  generate
    o: nsl_io.ddr.ddr_output
      port map(
        clock_i => clock_i,
        d_i(0) => d_i(i),
        d_i(1) => d_i(i + ddr_width),
        dd_o => dd_o(i)
        );
  end generate;

end architecture;
