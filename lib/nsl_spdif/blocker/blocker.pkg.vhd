library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.spdif.all;
use work.framer.all;
use nsl_data.crc.crc_state;
use nsl_data.bytestream.byte_string;

package blocker is

  type channel_data_t is
  record
    aux : unsigned(3 downto 0);
    audio : unsigned(19 downto 0);
    valid: std_ulogic;
  end record;

  subtype aesebu_crc is crc_state(7 downto 0);
  constant aesebu_crc_init : aesebu_crc := x"ff";
  function aesebu_crc_update(init : aesebu_crc;
                             data : std_ulogic) return aesebu_crc;
  function aesebu_crc_update(init : aesebu_crc;
                             data : byte_string) return aesebu_crc;
  
  component block_tx is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Guards consumption of block data
      block_ready_o : out std_ulogic;
      block_user_i : in std_ulogic_vector(0 to 191);
      block_channel_status_i : in std_ulogic_vector(0 to 191);
      -- Automatically override the 8 last bits of block
      -- channel with AES/EBU CRC
      block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

      -- Guards consumption of audio/aux/valid data
      ready_o : out std_ulogic;
      a_i, b_i: in channel_data_t;

      -- To framer
      block_start_o : out std_ulogic;
      channel_o : out std_ulogic;
      frame_o : out frame_t;
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

      synced_o : out std_ulogic;

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
  
end package blocker;

package body blocker is

  use nsl_data.crc.crc_update;

  constant aesebu_crc_poly : aesebu_crc := x"b8";
  constant aesebu_crc_insert_msb : boolean := true;
  constant aesebu_crc_pop_lsb : boolean := true;

  function aesebu_crc_update(init : aesebu_crc;
                             data : std_ulogic) return aesebu_crc is
  begin
    return crc_update(init,
                      aesebu_crc_poly,
                      aesebu_crc_insert_msb,
                      data);
  end function;

  function aesebu_crc_update(init : aesebu_crc;
                             data : byte_string) return aesebu_crc is
  begin
    return crc_update(init,
                      aesebu_crc_poly,
                      aesebu_crc_insert_msb,
                      aesebu_crc_pop_lsb,
                      data);
  end function;

end package body;
