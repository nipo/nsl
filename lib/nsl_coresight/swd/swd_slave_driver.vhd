library ieee;
use ieee.std_logic_1164.all;

library nsl_io, work, nsl_clocking;
use work.swd.all;

entity swd_slave_driver is
  generic(
    clock_buffer_mode_c: string := "global"
    );
  port(
    swd_i: in swd_slave_o;
    swd_o: out swd_slave_i;
    swdio_io: inout std_logic;
    swclk_i: in std_ulogic
    );
end entity;

architecture beh of swd_slave_driver is
begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    generic map(
      mode_c => clock_buffer_mode_c
      )
    port map(
      clock_i => swclk_i,
      clock_o => swd_o.clk
      );

  swdio: nsl_io.io.directed_io_driver
    port map(
      v_i => swd_i.dio,
      v_o => swd_o.dio,
      io_io => swdio_io
      );

end architecture;
