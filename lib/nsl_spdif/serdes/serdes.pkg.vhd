library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package serdes is

  type spdif_symbol_t is (
    -- Start of Block
    SPDIF_SYNC_B,
    -- Start of Frame
    SPDIF_SYNC_M,
    -- Subframe in Frame
    SPDIF_SYNC_W,
    SPDIF_0,
    SPDIF_1
    );

  component spdif_serializer is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i : in std_ulogic;
      symbol_i : in spdif_symbol_t;
      ready_o : out std_ulogic;

      data_o : out std_ulogic
      );
  end component;

  component spdif_deserializer is
    generic(
      clock_i_hz_c : natural;
      data_rate_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      synced_o : out std_ulogic;
      ui_tick_o : out std_ulogic;

      symbol_o : out spdif_symbol_t;
      valid_o : out std_ulogic;

      data_i : in std_ulogic
      );
  end component;
  
end package serdes;
