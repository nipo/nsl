library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2s, nsl_clocking, nsl_math;

entity i2s_receiver_slave is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_i : in  std_ulogic;
    ws_i  : in  std_ulogic;
    sd_i  : in  std_ulogic;

    valid_o : out std_ulogic;
    channel_o : out std_ulogic;
    data_o  : out unsigned
    );
end entity;

architecture beh of i2s_receiver_slave is

  signal sck, ws, sd : std_ulogic;
  
begin

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 3
      )
    port map(
      clock_i => clock_i,
      data_i(0) => sd_i,
      data_i(1) => ws_i,
      data_i(2) => sck_i,
      data_o(0) => sd,
      data_o(1) => ws,
      data_o(2) => sck
      );

  receiver: nsl_i2s.receiver.i2s_receiver
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sck_i => sck,
      ws_i => ws,
      sd_i => sd,

      valid_o => valid_o,
      channel_o => channel_o,
      data_o => data_o
      );

end architecture;
