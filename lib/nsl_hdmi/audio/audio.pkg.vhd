library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_spdif, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.hdmi.all;

package audio is

  function di_audio_clock_regen(cts, n: unsigned(19 downto 0)) return data_island_t;

  component hdmi_spdif_di_encoder is
    generic(
      audio_clock_divisor_c: natural := 4096
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      cts_send_i : in std_ulogic;
      cts_i : in unsigned(19 downto 0);

      enable_i : in std_ulogic := '1';

      -- SPDIF block input
      block_ready_o : out std_ulogic;
      block_valid_i : in std_ulogic := '1';
      block_user_i : in std_ulogic_vector(0 to 191);
      block_channel_status_i : in std_ulogic_vector(0 to 191);
      block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

      -- PCM data input
      ready_o : out std_ulogic;
      valid_i : in std_ulogic := '1';
      a_i, b_i: in nsl_spdif.blocker.channel_data_t;

      -- HDMI SOF marker from encoder
      sof_i : in std_ulogic := '0';

      -- DI stream
      di_valid_o : out std_ulogic;
      di_ready_i : in std_ulogic;
      di_o : out work.hdmi.data_island_t
      );
  end component;

  component hdmi_spdif_cts_counter is
    generic(
      audio_clock_divisor_c: natural := 4096
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      cts_o : out unsigned(19 downto 0);
      cts_send_o : out std_ulogic;

      spdif_tick_i : in std_ulogic
      );
  end component;

end package audio;

package body audio is

  function di_audio_clock_regen(cts, n: unsigned(19 downto 0)) return data_island_t
  is
    variable ret : data_island_t;
    constant tmp: byte_string(0 to 6) := to_be(x"000" & cts & x"0" & n);
  begin
    ret.packet_type := di_type_audio_clock_regen;
    ret.hb := from_hex("0000");
    ret.pb := tmp & tmp & tmp & tmp;
    return ret;
  end function;

end package body;
