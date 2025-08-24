library ieee;
use ieee.std_logic_1164.all;

library work, nsl_io;
use work.flit.all;
use work.rgmii.all;
use work.gmii.all;
use work.link.all;
use nsl_io.diff.all;

entity gmii_to_rgmii is
  generic(
    clock_delay_ps_c: natural := 0
    );
  port(
    gmii_clk_i : in std_ulogic;
    gmii_i : in work.gmii.gmii_io_group_t;

    rgmii_o : out work.rgmii.rgmii_io_group_t
    );
end entity;

architecture beh of gmii_to_rgmii is

  signal ddr_io_txd  : std_ulogic_vector(11 downto 0);
  signal rgmii_group : work.rgmii.rgmii_io_group_t;
  
begin

  ddr_io_txd(3 downto 0) <= gmii_i.data(3 downto 0);
  ddr_io_txd(4) <= gmii_i.en;
  ddr_io_txd(5) <= '1';
  ddr_io_txd(9 downto 6) <= gmii_i.data(7 downto 4);
  ddr_io_txd(10) <= gmii_i.en xor gmii_i.er;
  ddr_io_txd(11) <= '0';
  
  ddr_output: nsl_io.ddr.ddr_bus_output
    generic map(
      ddr_width => 6
      )
    port map(
      clock_i          => to_diff(gmii_clk_i),
      d_i              => ddr_io_txd,
      dd_o(3 downto 0) => rgmii_group.d,
      dd_o(4)          => rgmii_group.ctl,
      dd_o(5)          => rgmii_group.c
      );

  clock_delay: nsl_io.delay.output_delay_fixed
    generic map(
      delay_ps_c => clock_delay_ps_c
      )
    port map(
      data_i => rgmii_group.c,
      data_o => rgmii_o.c
      );
  rgmii_o.ctl <= rgmii_group.ctl;
  rgmii_o.d <= rgmii_group.d;

end architecture;
