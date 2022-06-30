library ieee;
use ieee.std_logic_1164.all;

library nsl_io, work;
use work.swd.all;

entity swd_master_driver is
  port(
    swd_i: in swd_master_o;
    swd_o: out swd_master_i;
    swdio_io: inout std_logic;
    swclk_o: out std_ulogic
    );
end entity;

architecture beh of swd_master_driver is
begin

  swclk_o <= swd_i.clk;
  swdio: nsl_io.io.directed_io_driver
    port map(
      v_i => swd_i.dio,
      v_o => swd_o.dio,
      io_io => swdio_io
      );

end architecture;
