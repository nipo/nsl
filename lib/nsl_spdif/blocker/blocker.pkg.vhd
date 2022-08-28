library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.spdif.all;
use work.framer.all;
use nsl_data.bytestream.byte_string;

package blocker is

  type channel_data_t is
  record
    aux : unsigned(3 downto 0);
    audio : unsigned(19 downto 0);
    valid: std_ulogic;
  end record;
  
  component block_tx is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Guards consumption of block data
      block_ready_o : out std_ulogic;
      block_valid_i : in std_ulogic := '1';
      block_user_i : in std_ulogic_vector(0 to 191);
      block_channel_status_i : in std_ulogic_vector(0 to 191);
      -- Automatically override the 8 last bits of block
      -- channel with AES/EBU CRC
      block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

      -- Guards consumption of audio/aux/valid data
      ready_o : out std_ulogic;
      valid_i : in std_ulogic := '1';
      a_i, b_i: in channel_data_t;

      -- To framer
      block_start_o : out std_ulogic;
      channel_o : out std_ulogic;
      frame_o : out frame_t;
      valid_o : out std_ulogic;
      ready_i : in std_ulogic
      );
  end component;

  component block_rx is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From framer
      synced_i : in std_ulogic;
      block_start_i : in std_ulogic;
      channel_i : in std_ulogic;
      frame_i : in frame_t;
      parity_ok_i : in std_ulogic;
      valid_i : in std_ulogic;
      ready_o : out std_ulogic;

      synced_o : out std_ulogic;

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
  end component;
  
end package blocker;
