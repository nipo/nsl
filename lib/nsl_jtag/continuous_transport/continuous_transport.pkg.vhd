library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

-- Continuous-shift, full-duplex byte transport over a single JTAG
-- Shift-DR run. See continuous_transport.md for the protocol
-- specification. This layer is transport only: byte framing, in-order
-- delivery, flow control and truncation-safety. Integrity and
-- retransmission belong to the layer above.
package continuous_transport is

  -- Wire constants (see spec section 4).
  -- JTAG shifts LSB-first: 0x55 is a steady alternation, 0xd5 ends in
  -- two equal bits and breaks it, marking the SOF (Ethernet-style).
  constant preamble_byte_c   : byte := x"55";
  constant preamble_min_c    : positive := 2;
  constant sof_byte_c        : byte := x"d5";

  -- Header decode (see spec section 4.1).
  -- Data frame:    0b0L nnnnnn  (L = last/end-of-packet, nnnnnn = len-1)
  -- Control frame: 0b1x xxxxxx
  constant hdr_control_bit_c : natural := 7; -- '1' => control frame
  constant hdr_last_bit_c    : natural := 6; -- within data, '1' => EOP
  -- length-1 lives in bits 5 downto 0 of a data header

  constant data_header_mask_c : byte := "0-------";
  constant control_mask_c : byte := "1-------";

  -- Defined control opcodes are clustered under the 0b1111xxxx prefix so
  -- the 0b10xxxxxx (64), 0b110xxxxx (32) and 0b1110xxxx (16) blocks stay
  -- reserved and aligned for future inline-value opcodes.
  constant ctl_idle_c        : byte := "11110000";
  constant ctl_credit_c      : byte := "11110001"; -- +2 bytes LE
  constant ctl_tx_level_c    : byte := "11110010"; -- TDO, +2 bytes LE
  -- Set TDO alignment pad: 8 opcodes carry the 3-bit pad in place, no
  -- payload byte. ctl_set_tdo_pad_base_c or pad(2:0). TDI only.
  constant ctl_set_tdo_pad_base_c : byte := "11111---";

  constant data_bytes_max_l2_c  : positive := 6;
  constant data_bytes_max_c  : positive := 2 ** data_bytes_max_l2_c;
  constant credit_bits_c     : positive := 16;

  -- Worst-case internal TAP pipeline latency, in TCK cycles, folded by
  -- the host into credit timing (spec section 6). Deliberately
  -- pessimistic: generosity here costs ~0.1% throughput, so there is no
  -- need to characterise it tightly.
  constant tap_tx_latency_c  : natural := 16;
  constant tap_rx_latency_c  : natural := 16;

  -- TAP-side slave: terminates the protocol against a custom DR (selected by
  -- reg_id_c) and exposes a system-clock framed byte interface in each
  -- direction. Binds to the on-chip TAP through nsl_hwdep.jtag.jtag_tap_register.
  component continuous_transport_slave is
    generic(
      reg_id_c         : natural range 1 to 4;
      -- RX FIFO must absorb a full batch to support blind, long-latency
      -- adapter batches without a mid-stream stall (spec section 6.1).
      rx_fifo_depth_c  : positive;
      tx_fifo_depth_c  : positive;
      preamble_count_c : positive := preamble_min_c
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;
      -- Asserted (low) on TLR, resynchronised to clock_i; resets the
      -- transport and is offered for resetting user logic (spec sec 9).
      reset_n_o : out std_ulogic;

      -- System -> ATE (TDO direction).
      tx_i : in  nsl_bnoc.framed.framed_req_t;
      tx_o : out nsl_bnoc.framed.framed_ack_t;

      -- ATE -> System (TDI direction).
      rx_o : out nsl_bnoc.framed.framed_req_t;
      rx_i : in  nsl_bnoc.framed.framed_ack_t
      );
  end component;

  component continuous_transport_core is
    generic(
      preamble_count_c : positive := preamble_min_c
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      shift_i   : in  std_ulogic;
      capture_i : in  std_ulogic;
      update_i  : in  std_ulogic;
      tdi_i     : in  std_ulogic;
      tdo_o     : out std_ulogic;

      rx_data_o  : out byte;
      rx_last_o  : out std_ulogic;
      rx_valid_o : out std_ulogic;
      rx_free_i  : in  unsigned(credit_bits_c-1 downto 0);

      tx_data_i  : in  byte;
      tx_last_i  : in  std_ulogic;
      tx_valid_i : in  std_ulogic;
      tx_ready_o : out std_ulogic;
      tx_level_i : in  unsigned(credit_bits_c-1 downto 0)
      );
  end component;

  component continuous_transport_deserializer is
    port(
      clock_i   : in  std_ulogic;         -- TCK
      reset_n_i : in  std_ulogic;

      shift_i   : in  std_ulogic;         -- one bit exchanged when '1'
      capture_i : in  std_ulogic;         -- Capture-DR: batch start
      tdi_i     : in  std_ulogic;         -- incoming bit

      locked_o     : out std_ulogic;      -- SOF acquired for this batch
      byte_o       : out byte;
      byte_valid_o : out std_ulogic       -- one-cycle strobe per framed byte
      );
  end component;

  component continuous_transport_deframer is
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      -- Framed byte stream from the deserializer.
      byte_i       : in  byte;
      byte_valid_i : in  std_ulogic;

      -- Recovered payload (to the RX FIFO write side).
      rx_data_o  : out byte;
      rx_last_o  : out std_ulogic;
      rx_valid_o : out std_ulogic;

      -- Decoded control, each a one-cycle strobe with its value.
      budget_o     : out unsigned(credit_bits_c-1 downto 0);
      budget_set_o : out std_ulogic;
      pad_o        : out std_ulogic_vector(2 downto 0);
      pad_set_o    : out std_ulogic
      );
  end component;

  component continuous_transport_framer is
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      capture_i : in  std_ulogic;

      byte_ready_i : in  std_ulogic;
      byte_o       : out byte;

      budget_set_i : in  std_ulogic;
      budget_i     : in  unsigned(credit_bits_c-1 downto 0);

      tx_data_i  : in  byte;
      tx_last_i  : in  std_ulogic;
      tx_valid_i : in  std_ulogic;
      tx_ready_o : out std_ulogic;

      rx_free_i : in  unsigned(credit_bits_c-1 downto 0);

      tx_level_i : in  unsigned(credit_bits_c-1 downto 0)
      );
  end component;

  component continuous_transport_serializer is
    generic(
      preamble_count_c : positive := preamble_min_c
      );
    port(
      clock_i   : in  std_ulogic;         -- TCK
      reset_n_i : in  std_ulogic;

      shift_i   : in  std_ulogic;         -- one bit exchanged when '1'
      capture_i : in  std_ulogic;         -- Capture-DR: batch start
      update_i  : in  std_ulogic;         -- Update-DR: batch end
      pad_i     : in  integer range 0 to 7;  -- active alignment pad

      tdo_o     : out std_ulogic;         -- outgoing bit (combinational)

      byte_i      : in  byte;  -- next payload byte
      byte_ready_o : out std_ulogic        -- payload byte latched, advance framer
      );
  end component;

end package;
