library ieee;
use ieee.std_logic_1164.all;

library work, nsl_io, nsl_clocking;
use work.flit.all;
use work.rgmii.all;
use work.gmii.all;
use work.link.all;
use nsl_io.diff.all;

entity rgmii_to_gmii is
  generic(
    clock_delay_ps_c: natural := 0
    );
  port(
    rgmii_i : in  work.rgmii.rgmii_io_group_t;

    gmii_clk_o : out std_ulogic;
    gmii_o : out  work.gmii.gmii_io_group_t
    );
end entity;

architecture beh of rgmii_to_gmii is

  signal rgmii_s : work.rgmii.rgmii_io_group_t;
  signal gmii_s : work.gmii.gmii_io_group_t;
  signal clock_s : std_ulogic;
  signal diff_clock_s : diff_pair;
  
begin

  clock_delay: nsl_io.delay.input_delay_fixed
    generic map(
      delay_ps_c => clock_delay_ps_c
      )
    port map(
      data_i => rgmii_i.c,
      data_o => rgmii_s.c
      );
  rgmii_s.ctl <= rgmii_i.ctl;
  rgmii_s.d <= rgmii_i.d;

  from_rgmii_clock: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => rgmii_s.c,
      clock_o => clock_s
      );

  diff_clock_s <= swap(to_diff(clock_s));
  
  ddr_input: nsl_io.ddr.ddr_bus_input
    generic map(
      ddr_width => 5
      )
    port map(
      clock_i          => diff_clock_s,
      dd_i(3 downto 0) => rgmii_s.d,
      dd_i(4)          => rgmii_s.ctl,
      d_o(3 downto 0)  => gmii_s.data(3 downto 0),
      d_o(4)           => gmii_s.en,
      d_o(8 downto 5)  => gmii_s.data(7 downto 4),
      d_o(9)           => gmii_s.er
      );

  gmii_clk_o <= clock_s;
  gmii_o.data <= gmii_s.data;
  gmii_o.en <= gmii_s.en;
  gmii_o.er <= gmii_s.en xor gmii_s.er;
  
end architecture;
