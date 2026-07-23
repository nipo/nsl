library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;

package stream_apb is

  -- Stream-to-APB command bridge.
  --
  -- Terminates a byte-oriented AXI4-Stream (one byte per beat, with
  -- `last`) carrying commands, and acts as an APB master. It exposes an
  -- APB address space (registers, ROM, memory) over the stream through
  -- three commands. Every response frame ends with a status byte
  -- (bit 0 = error).
  --
  -- Commands (first byte is the opcode, multi-byte fields little-endian):
  --   identify [0xff, 0x00]
  --     -> [ identify_c..., status ]
  --   read     [0x80, address(addr bytes), count(count bytes)]
  --     -> [ data... (little-endian), status ]
  --   write    [0x00, address(addr bytes), data... (whole words)]
  --     -> [ status ]
  --
  -- Address is a word-aligned byte address; the read count field carries
  -- (word count - 1), so 0 reads one word. Read/write addresses
  -- auto-increment by one word. A command frame that ends (`last`) before
  -- its opcode/address/count is complete is answered with an error
  -- status. `identify_c` is the payload served for the identify command
  -- (the bridge appends status).
  component apb_stream_bridge is
    generic (
      apb_config_c : nsl_amba.apb.config_t;
      stream_config_c : nsl_amba.axi4_stream.config_t;
      burst_length_l2_c : natural;
      identify_c : nsl_data.bytestream.byte_string
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Command stream in
      rx_i : in nsl_amba.axi4_stream.master_t;
      rx_o : out nsl_amba.axi4_stream.slave_t;

      -- Response stream out
      tx_o : out nsl_amba.axi4_stream.master_t;
      tx_i : in nsl_amba.axi4_stream.slave_t;

      -- APB master
      apb_o : out nsl_amba.apb.master_t;
      apb_i : in nsl_amba.apb.slave_t
      );
  end component;

end package;
