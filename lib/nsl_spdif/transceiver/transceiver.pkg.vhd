library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.blocker.all;

package transceiver is
  
  component spdif_tx is
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
  end component;

  component spdif_rx_recovery is
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
      block_user_o : out std_ulogic_vector(0 to 191);
      block_channel_status_o : out std_ulogic_vector(0 to 191);
      block_channel_status_aesebu_crc_ok_o : out std_ulogic;

      -- Guards audio/aux/valid data
      valid_o : out std_ulogic;
      a_o, b_o: out channel_data_t
      );
  end component;
  
end package transceiver;
