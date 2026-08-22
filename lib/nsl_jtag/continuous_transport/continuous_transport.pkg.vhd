library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_bnoc.chunked_link.all;

-- Continuous-shift, full-duplex byte transport over a single JTAG
-- Shift-DR run. See continuous_transport.md for the transport
-- specification; the byte-level frame and credit protocol is
-- nsl_bnoc.chunked_link. This layer is transport only: byte framing,
-- in-order delivery, flow control and truncation-safety. Integrity and
-- retransmission belong to the layer above.
package continuous_transport is

  -- Wire constants (see spec section 4).
  -- JTAG shifts LSB-first: 0x55 is a steady alternation, 0xd5 ends in
  -- two equal bits and breaks it, marking the SOF (Ethernet-style).
  constant preamble_byte_c   : byte := x"55";
  constant preamble_min_c    : positive := 2;
  constant sof_byte_c        : byte := x"d5";

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

  component jtag_continuous_transport_tap is
    generic(
      tx_fifo_depth_c : natural := 256;
      rx_fifo_depth_c : natural := 256
      );
    port(
      chip_tck_i : in std_ulogic := '0';
      chip_tms_i : in std_ulogic := '0';
      chip_tdi_i : in std_ulogic := '0';
      chip_tdo_o : out std_ulogic;

      -- Clocks the fifo, asynchronous to TCK of user reg
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;
      reset_n_o   : out std_ulogic;

      tx_i : in nsl_bnoc.framed.framed_req;
      tx_o : out nsl_bnoc.framed.framed_ack;

      rx_o : out nsl_bnoc.framed.framed_req;
      rx_i : in nsl_bnoc.framed.framed_ack
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
