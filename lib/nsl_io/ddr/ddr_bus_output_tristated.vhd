library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_bus_output_tristated is
  generic(
    ddr_width : natural
    );
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i : in std_ulogic_vector(2 * ddr_width - 1 downto 0);
    oe_i : in std_ulogic;
    pad_o : out nsl_io.io.tristated_vector(ddr_width - 1 downto 0)
    );
end entity;

architecture beh of ddr_bus_output_tristated is

begin

  lane: for i in 0 to ddr_width - 1
  generate
    inst: nsl_io.ddr.ddr_output_tristated
      port map(
        clock_i => clock_i,
        d_i => d_i(i * 2 + 1 downto i * 2),
        oe_i => oe_i,
        pad_o => pad_o(i)
        );
  end generate;

end architecture;
