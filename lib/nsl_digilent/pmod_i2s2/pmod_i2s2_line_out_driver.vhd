library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_i2s;

entity pmod_i2s2_line_out_driver is
  port(
    pmod_io: inout work.pmod.pmod_double_t;

    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    mclk_i : in std_ulogic;
    sck_i : in std_ulogic;
    ws_i : in std_ulogic;

    ready_o : out std_ulogic;
    channel_o : out std_ulogic;
    data_i : in unsigned
    );
end entity;

architecture beh of pmod_i2s2_line_out_driver is

  signal sd_s : std_ulogic;

begin

  tx: nsl_i2s.transmitter.i2s_transmitter
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sck_i => sck_i,
      ws_i => ws_i,
      sd_o => sd_s,

      ready_o => ready_o,
      channel_o => channel_o,
      data_i => data_i
      );

  pmod_io(1) <= mclk_i;
  pmod_io(2) <= ws_i;
  pmod_io(3) <= sck_i;
  pmod_io(4) <= sd_s;

end architecture;
