library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.spdif.all;
use work.serdes.all;

package framer is

  type frame_t is
  record
    aux : unsigned(3 downto 0);
    audio : unsigned(19 downto 0);
    invalid : std_ulogic;
    user : std_ulogic;
    channel_status : std_ulogic;
  end record;
  
  component spdif_framer is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- 0/1=x/B. Should be 1 if start of block.
      block_start_i : in std_ulogic;
      -- 0/1=M/W. Should be 0 if start of block.
      channel_i : in std_ulogic;
      frame_i : in frame_t;
      ready_o : out std_ulogic;
      
      symbol_o : out spdif_symbol_t;
      ready_i : in std_ulogic
      );
  end component;

  component spdif_unframer is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      
      symbol_i : in spdif_symbol_t;
      synced_i : in std_ulogic;
      valid_i : in std_ulogic;

      synced_o : out std_ulogic;
      -- 0/1=x/B. Should be 1 if start of block.
      block_start_o : out std_ulogic;
      -- 0/1=M/W. Should be 0 if start of block.
      channel_o : out std_ulogic;
      frame_o : out frame_t;
      parity_ok_o : out std_ulogic;
      valid_o : out std_ulogic
      );
  end component;
  
end package framer;
