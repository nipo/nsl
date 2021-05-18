library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2s, nsl_clocking, nsl_math;

entity i2s_receiver_master is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_div_m1_i : in unsigned;

    sck_o : out std_ulogic;
    ws_o  : out std_ulogic;
    sd_i  : in  std_ulogic;

    valid_o : out std_ulogic;
    channel_o : out std_ulogic;
    data_o  : out unsigned
    );
end entity;

architecture beh of i2s_receiver_master is

  signal sck, ws, sd : std_ulogic;
  constant word_width_m1 : unsigned(nsl_math.arith.log2(data_o'length)-1 downto 0)
    := to_unsigned(data_o'length - 1, nsl_math.arith.log2(data_o'length));
  
begin

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 1
      )
    port map(
      clock_i => clock_i,
      data_i(0) => sd_i,
      data_o(0) => sd
      );

  clock_gen: nsl_i2s.clock.i2s_clock_generator
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      sck_div_m1_i => sck_div_m1_i,
      word_width_m1_i => word_width_m1,
      sck_o => sck,
      ws_o => ws
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

  sck_o <= sck;
  ws_o <= ws;
  
end architecture;
