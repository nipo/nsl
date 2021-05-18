library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2s, nsl_clocking, nsl_math;

entity i2s_transmitter_slave is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_i : in std_ulogic;
    ws_i  : in std_ulogic;
    sd_o  : out std_ulogic;

    ready_o : out std_ulogic;
    channel_o : out std_ulogic;
    data_i  : in unsigned
    );
end entity;

architecture beh of i2s_transmitter_slave is

  signal sck, ws : std_ulogic;
  constant word_width_m1 : unsigned(nsl_math.arith.log2(data_i'length)-1 downto 0)
    := to_unsigned(data_i'length - 1, nsl_math.arith.log2(data_i'length));
  
begin

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 2
      )
    port map(
      clock_i => clock_i,
      data_i(0) => ws_i,
      data_i(1) => sck_i,
      data_o(0) => ws,
      data_o(1) => sck
      );
  
  transmitter: nsl_i2s.transmitter.i2s_transmitter
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sck_i => sck,
      ws_i => ws,
      sd_o => sd_o,

      ready_o => ready_o,
      channel_o => channel_o,
      data_i => data_i
      );
  
end architecture;
