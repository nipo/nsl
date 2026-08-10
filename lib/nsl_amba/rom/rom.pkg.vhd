library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_memory;
use nsl_memory.rom.rom_implementation_t;

package rom is

  -- APB read-only memory completer. It serves `contents_c` as a
  -- read-only region on an APB bus. Contents are zero-padded up to the
  -- next power-of-two word count (word = data bus width). Reads return
  -- the stored words little-endian; writes complete with SLVERR.
  component apb_rom is
    generic (
      config_c : nsl_amba.apb.config_t;
      implementation_c : rom_implementation_t := ROM_BLOCK;
      contents_c : nsl_data.bytestream.byte_string
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic := '1';

      apb_i : in nsl_amba.apb.master_t;
      apb_o : out nsl_amba.apb.slave_t
      );
  end component;

end package;
