library ieee;
use ieee.std_logic_1164.all;

library hwdep;
library signalling;

entity io_ddr_bus_output is
  generic(
    ddr_width : natural
    );
  port(
    p_clk   : in  signalling.diff.diff_pair;
    p_d     : in  std_ulogic_vector(2 * ddr_width - 1 downto 0);
    p_dd    : out std_ulogic_vector(ddr_width - 1 downto 0)
    );
end entity;

architecture rtl of io_ddr_bus_output is
begin

  bus_loop: for i in p_dd'range
  generate
    d_o: hwdep.io.io_ddr_output
      port map(
        p_clk => p_clk,
        p_d(0) => p_d(i),
        p_d(1) => p_d(i + ddr_width),
        p_dd => p_dd(i)
        );
  end generate;

end architecture;
