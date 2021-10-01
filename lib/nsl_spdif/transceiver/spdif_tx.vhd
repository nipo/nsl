library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.blocker.all;

entity spdif_tx is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- UI clock tick
    ui_tick_i : in std_ulogic;

    -- Guards consumption of block data
    block_ready_o : out std_ulogic;
    block_user_i : in std_ulogic_vector(0 to 191);
    block_channel_status_i : in std_ulogic_vector(0 to 191);
    block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

    -- Guards consumption of audio/aux/valid data
    ready_o : out std_ulogic;
    a_i, b_i: in channel_data_t;

    -- Encoded signal
    spdif_o : out std_ulogic
    );
end entity;

architecture beh of spdif_tx is

  signal s_framer_block_start : std_ulogic;
  signal s_framer_channel : std_ulogic;
  signal s_framer_frame : work.framer.frame_t;
  signal s_framer_ready : std_ulogic;

  signal s_ser_symbol : work.serdes.spdif_symbol_t;
  signal s_ser_ready : std_ulogic;

begin

  blocker: work.blocker.block_tx
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      block_ready_o => block_ready_o,
      block_user_i => block_user_i,
      block_channel_status_i => block_channel_status_i,
      block_channel_status_aesebu_auto_crc_i => block_channel_status_aesebu_auto_crc_i,

      ready_o => ready_o,
      a_i => a_i,
      b_i => b_i,

      block_start_o => s_framer_block_start,
      channel_o => s_framer_channel,
      frame_o => s_framer_frame,
      ready_i => s_framer_ready
      );

  framer: work.framer.spdif_framer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      block_start_i => s_framer_block_start,
      channel_i => s_framer_channel,
      frame_i => s_framer_frame,
      ready_o => s_framer_ready,

      symbol_o => s_ser_symbol,
      ready_i => s_ser_ready
      );
  
  serdes: work.serdes.spdif_serializer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      tick_i => ui_tick_i,
      symbol_i => s_ser_symbol,
      ready_o => s_ser_ready,

      data_o => spdif_o
      );

end architecture;
