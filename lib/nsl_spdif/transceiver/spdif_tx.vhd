library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spdif, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_spdif.blocker.all;

entity spdif_tx is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- UI clock tick
    ui_tick_i : in std_ulogic;

    -- Guards consumption of block data
    block_ready_o : out std_ulogic;
    block_valid_i : in std_ulogic := '1';
    block_user_i : in byte_string(0 to 23);
    block_channel_status_i : in byte_string(0 to 23);
    block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

    -- Guards consumption of audio/aux/valid data
    ready_o : out std_ulogic;
    valid_i : in std_ulogic := '1';
    a_i, b_i: in channel_data_t;

    -- Encoded signal
    spdif_o : out std_ulogic
    );
end entity;

architecture beh of spdif_tx is

  signal s_framer_block_start : std_ulogic;
  signal s_framer_channel : std_ulogic;
  signal s_framer_frame : nsl_spdif.framer.frame_t;
  signal s_framer_ready : std_ulogic;

  signal s_ser_symbol : nsl_spdif.serdes.spdif_symbol_t;
  signal s_ser_ready : std_ulogic;
  signal block_user_s, block_channel_status_s: std_ulogic_vector(0 to 191);

begin

  block_user_s <= bitswap(std_ulogic_vector(from_be(block_user_i)));
  block_channel_status_s <= bitswap(std_ulogic_vector(from_be(block_channel_status_i)));
  
  blocker: nsl_spdif.blocker.block_tx
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      block_ready_o => block_ready_o,
      block_valid_i => block_valid_i,
      block_user_i => block_user_s,
      block_channel_status_i => block_channel_status_s,
      block_channel_status_aesebu_auto_crc_i => block_channel_status_aesebu_auto_crc_i,

      ready_o => ready_o,
      valid_i => valid_i,
      a_i => a_i,
      b_i => b_i,

      block_start_o => s_framer_block_start,
      channel_o => s_framer_channel,
      frame_o => s_framer_frame,
      ready_i => s_framer_ready
      );

  framer: nsl_spdif.framer.spdif_framer
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
  
  serdes: nsl_spdif.serdes.spdif_serializer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      tick_i => ui_tick_i,
      symbol_i => s_ser_symbol,
      ready_o => s_ser_ready,

      data_o => spdif_o
      );

end architecture;
