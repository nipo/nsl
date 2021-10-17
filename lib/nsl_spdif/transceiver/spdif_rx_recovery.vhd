library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.blocker.all;

entity spdif_rx_recovery is
  generic(
    clock_i_hz_c : natural;
    data_rate_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Encoded signal
    spdif_i: in std_ulogic;

    synced_o: out std_ulogic;
    -- Recovered UI tick
    ui_tick_o: out std_ulogic;

    -- Guards block data
    block_valid_o : out std_ulogic;
    block_ready_i : in std_ulogic := '1';
    block_user_o : out std_ulogic_vector(0 to 191);
    block_channel_status_o : out std_ulogic_vector(0 to 191);
    block_channel_status_aesebu_crc_ok_o : out std_ulogic;

    -- Guards audio/aux/valid data
    valid_o : out std_ulogic;
    ready_i : in std_ulogic := '1';
    a_o, b_o: out channel_data_t
    );
end entity;

architecture beh of spdif_rx_recovery is

  signal s_des_symbol : work.serdes.spdif_symbol_t;
  signal s_des_synced : std_ulogic;
  signal s_des_valid : std_ulogic;

  signal s_unf_synced : std_ulogic;
  signal s_unf_block_start : std_ulogic;
  signal s_unf_channel : std_ulogic;
  signal s_unf_frame : work.framer.frame_t;
  signal s_unf_parity_ok : std_ulogic;
  signal s_unf_valid : std_ulogic;

begin

  serdes: work.serdes.spdif_deserializer
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      data_rate_c => data_rate_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => spdif_i,
      
      synced_o => s_des_synced,
      ui_tick_o => ui_tick_o,

      symbol_o => s_des_symbol,
      valid_o => s_des_valid
      );

  framer: work.framer.spdif_unframer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      symbol_i => s_des_symbol,
      valid_i => s_des_valid,
      synced_i => s_des_synced,

      synced_o => s_unf_synced,
      block_start_o => s_unf_block_start,
      channel_o => s_unf_channel,
      frame_o => s_unf_frame,
      parity_ok_o => s_unf_parity_ok,
      valid_o => s_unf_valid
      );

  blocker: work.blocker.block_rx
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      synced_i => s_unf_synced,
      block_start_i => s_unf_block_start,
      channel_i => s_unf_channel,
      frame_i => s_unf_frame,
      parity_ok_i => s_unf_parity_ok,
      valid_i => s_unf_valid,

      synced_o => synced_o,
      
      block_valid_o => block_valid_o,
      block_ready_i => block_ready_i,
      block_user_o => block_user_o,
      block_channel_status_o => block_channel_status_o,
      block_channel_status_aesebu_crc_ok_o => block_channel_status_aesebu_crc_ok_o,

      valid_o => valid_o,
      ready_i => ready_i,
      a_o => a_o,
      b_o => b_o
      );
  
end architecture;
