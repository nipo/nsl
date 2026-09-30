library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

-- Bus transaction loggers.
package mm_logger is

  -- Channel indices of axi4_mm_logger
  constant axi4_mm_logger_channel_aw_c : natural := 0;
  constant axi4_mm_logger_channel_w_c : natural := 1;
  constant axi4_mm_logger_channel_b_c : natural := 2;
  constant axi4_mm_logger_channel_ar_c : natural := 3;
  constant axi4_mm_logger_channel_r_c : natural := 4;
  constant axi4_mm_logger_channel_count_c : natural := 5;

  -- Register byte offsets of axi4_mm_logger
  constant axi4_mm_logger_ctrl_c : natural := 16#000#;
  constant axi4_mm_logger_status_c : natural := 16#004#;
  constant axi4_mm_logger_timestamp_c : natural := 16#008#;
  constant axi4_mm_logger_config_c : natural := 16#00c#;
  constant axi4_mm_logger_count_c : natural := 16#010#;

  -- Passive monitor of an AXI4-MM bus.  It records every handshake of
  -- every channel with a timestamp into per-channel memories, readable
  -- over APB.
  --
  -- Recording
  -- =========
  --
  -- Every channel (AW=0, W=1, B=2, AR=3, R=4) has its own memory of
  -- 2**depth_l2_c entries, so handshakes of all channels in the same
  -- cycle are all recorded.  While CTRL.enable is set, every valid and
  -- ready cycle of a channel records an entry at index COUNT of that
  -- channel, and increments COUNT.  Once a channel's memory is full
  -- (COUNT = 2**depth_l2_c), further handshakes of this channel are
  -- dropped and set the channel's overflow flag.
  --
  -- Entries are four 32-bit words, word 0 at the lowest address:
  --
  -- * word 0: timestamp_i during the handshake cycle,
  --
  -- * AW/AR: w1 = addr[31:0]; w2 = id[15:0] | len_m1[7:0] << 16 |
  --   size_l2[2:0] << 24 | burst[1:0] << 27 | lock << 29; w3 =
  --   cache[3:0] | prot[2:0] << 4 | qos[3:0] << 8 | region[3:0] << 12 |
  --   stall << 24,
  --
  -- * W: w1 = data bytes 0 to 3 (byte lane 0 in bits 7:0), w2 = bytes
  --   4 to 7 (0 for a bus narrower than 64 bits), w3 = strb[7:0] | last
  --   << 8 | stall << 24,
  --
  -- * B: w1 = id[15:0] | resp[1:0] << 16; w2 = 0; w3 = stall << 24,
  --
  -- * R: w1 = data bytes 0 to 3, w2 = bytes 4 to 7, w3 = id[15:0] |
  --   resp[1:0] << 16 | last << 18 | stall << 24.
  --
  -- stall is the count of cycles the channel's valid was asserted
  -- without ready before the handshake, saturated at 255.  For B and R
  -- it measures backpressure from the master.
  --
  -- Fields are read through the axi4_mm accessors: fields absent from
  -- axi_config_c read 0, except size, burst and last which read the
  -- value the configuration implies (full bus width, INCR, last on
  -- every beat without bursts).  Byte lanes and strobes beyond the bus
  -- width read 0.  IDs wider than 16 bits and addresses wider than 32
  -- bits are truncated.  Data buses wider than 64 bits are rejected at
  -- elaboration.
  --
  -- Recording is one cycle behind the bus: an entry is written in the
  -- memory the cycle after its handshake.  COUNT includes it from the
  -- cycle after the handshake.
  --
  -- APB register map
  -- ================
  --
  -- apb_config_c must have a 32-bit data bus and at least depth_l2_c +
  -- 7 address bits.  Offset bits above depth_l2_c + 6 are ignored: the
  -- map repeats every 2**(depth_l2_c + 7) bytes.
  --
  -- * 0x000 CTRL: bit 0: enable, recording while set, reset 0.  bit 1:
  --   clear, writing 1 resets every COUNT and overflow flag, reads 0.
  --   A handshake in the cycle of a clear is not recorded.
  -- * 0x004 STATUS: bits 4:0: overflow flag of each channel.
  -- * 0x008 TIMESTAMP: timestamp_i now.
  -- * 0x00c CONFIG: depth_l2_c in bits 4:0, AXI data bus width as log2
  --   of bytes in bits 11:8, AXI ID width in bits 23:16.
  -- * 0x010 + 4 * c, c in 0 to 4: COUNT of channel c.
  -- * (c + 1) * 2**(depth_l2_c + 4) + 16 * i: entry i of channel c.
  --
  -- Other offsets read 0, writes other than to CTRL are ignored.  Reads
  -- take one wait state.
  --
  -- clock_i is the bus clock, APB is on the same clock.  reset_n_i is
  -- asynchronous.
  component axi4_mm_logger is
    generic(
      axi_config_c : nsl_amba.axi4_mm.config_t;
      apb_config_c : nsl_amba.apb.config_t;
      depth_l2_c : natural range 4 to 13 := 10
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      timestamp_i : in unsigned(31 downto 0);
      master_i : in nsl_amba.axi4_mm.master_t;
      slave_i : in nsl_amba.axi4_mm.slave_t;
      apb_i : in nsl_amba.apb.master_t;
      apb_o : out nsl_amba.apb.slave_t
      );
  end component;

end package;
