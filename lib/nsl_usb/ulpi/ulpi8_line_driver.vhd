library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_hwdep;
use nsl_usb.ulpi.all;

entity ulpi8_line_driver is
  generic(
    reset_active_c : std_ulogic := '1'
    );
  port(
    data_io: inout std_logic_vector(7 downto 0);
    dir_i: in std_ulogic;
    nxt_i: in std_ulogic;
    stp_o: out std_ulogic;
    reset_o: out std_ulogic;
    clock_i: in std_ulogic;

    ulpi_tap_o : out std_ulogic_vector(11 downto 0);

    bus_o : out ulpi8_phy2link;
    bus_i : in ulpi8_link2phy
    );
end entity ulpi8_line_driver;

architecture beh of ulpi8_line_driver is

  signal last_dir: std_ulogic;

begin

  dir_reg: process(clock_i)
  begin
    if rising_edge(clock_i) then
      last_dir <= dir_i;

      ulpi_tap_o(11) <= bus_i.reset;
      ulpi_tap_o(10) <= bus_i.stp;
      ulpi_tap_o(9) <= nxt_i;
      ulpi_tap_o(8) <= dir_i;
      ulpi_tap_o(7 downto 0) <= std_ulogic_vector(data_io);
    end if;
  end process;

  reset_o <= reset_active_c when bus_i.reset = '1' else not reset_active_c;
  stp_o <= bus_i.stp;

  data_io <= std_logic_vector(bus_i.data) when dir_i = '0' and last_dir = '0' else (others => 'Z');
  bus_o.data <= std_ulogic_vector(data_io) when dir_i = '1' and last_dir = '1' else (others => '-');

  clock_buffer_inst: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => clock_i,
      clock_o => bus_o.clock
      );
  bus_o.dir <= dir_i;
  bus_o.nxt <= nxt_i;
  
end architecture;
