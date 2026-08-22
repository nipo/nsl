library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

-- Credit-based chunk framing for full-duplex byte pipes. See
-- chunked_link.md for the protocol specification.
--
-- This layer turns a pair of nsl_bnoc.framed streams into a
-- back-to-back byte-oriented frame stream suitable for links where
-- one end (the master) owns all clocking and the other (the slave) is
-- purely reactive: JTAG continuous Shift-DR runs, SPI transactions.
-- It provides packet framing, in-order delivery and flow control in
-- both directions; the transport below provides the byte pipe, batch
-- delimitation and byte alignment.
package chunked_link is

  -- Header decode (see spec).
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
  constant ctl_tx_level_c    : byte := "11110010"; -- slave -> master, +2 bytes LE
  -- Set alignment pad: 8 opcodes carry the 3-bit pad in place, no
  -- payload byte. ctl_set_pad_base_c or pad(2:0). Master -> slave only;
  -- used by transports that need sub-byte alignment of the return
  -- stream (JTAG), ignored elsewhere.
  constant ctl_set_pad_base_c : byte := "11111---";

  constant data_bytes_max_l2_c  : positive := 6;
  constant data_bytes_max_c  : positive := 2 ** data_bytes_max_l2_c;
  constant credit_bits_c     : positive := 16;

  -- Staging buffer between a framed TX stream and a frame sender. Drains
  -- the TX stream into a chunk of up to data_bytes_max_c bytes so a
  -- length-prefixed data header can be emitted with the byte count and
  -- last flag known up front. A chunk closes on end-of-packet, on
  -- reaching full size, or on a TX bubble (so a slow producer cannot
  -- stall the link mid-frame).
  --
  -- While chunk_valid_o is asserted, chunk_byte_o presents the first
  -- unsent byte, chunk_last_o tells whether the chunk ends a packet, and
  -- chunk_len_m1_o counts the bytes still to send. Each chunk_next_i
  -- pulse consumes one byte; the buffer refills once all are consumed.
  -- A chunk survives batch boundaries: whatever is unsent stays
  -- presented for the sender to re-frame.
  component chunked_link_chunker is
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      tx_data_i  : in  byte;
      tx_last_i  : in  std_ulogic;
      tx_valid_i : in  std_ulogic;
      tx_ready_o : out std_ulogic;

      chunk_valid_o  : out std_ulogic;
      chunk_byte_o   : out byte;
      chunk_len_m1_o : out unsigned(data_bytes_max_l2_c-1 downto 0);
      chunk_last_o   : out std_ulogic;
      chunk_next_i   : in  std_ulogic
      );
  end component;

  -- Slave-side frame sender. Emits data frames gated by the TX budget
  -- granted by the master (absolute grants, every emitted byte spends
  -- one unit); when no data frame can be started it emits credit
  -- refreshes advertising rx_free_i, or tx-level frames whenever the
  -- backlog changed since last advertised. byte_o must be latched by
  -- the transport exactly once per byte_ready_i pulse.
  component chunked_link_slave_framer is
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      -- Batch start: budget back to zero, emission restarts with control.
      batch_start_i : in std_ulogic;

      -- One byte was latched by the transport; advance and present the
      -- next byte.
      byte_ready_i : in  std_ulogic;
      byte_o       : out byte;

      -- TX budget grant from the deframer (absolute).
      budget_set_i : in  std_ulogic;
      budget_i     : in  unsigned(credit_bits_c-1 downto 0);

      -- TX stream (payload to send).
      tx_data_i  : in  byte;
      tx_last_i  : in  std_ulogic;
      tx_valid_i : in  std_ulogic;
      tx_ready_o : out std_ulogic;

      -- RX buffer free space to advertise to the master (credit frames).
      rx_free_i : in  unsigned(credit_bits_c-1 downto 0);

      -- TX backlog to advertise to the master (tx-level frames): after
      -- each end-of-packet, and in place of idle whenever the value
      -- changed since last advertised.
      tx_level_i : in  unsigned(credit_bits_c-1 downto 0)
      );
  end component;

  -- Master-side frame sender. Emits data frames gated by the slave's
  -- advertised RX credit (absolute; only data bytes spend it), derated
  -- by flight_margin_c to cover bytes in flight when the credit value
  -- was captured. Emits TX budget grants toward the slave on demand
  -- through the grant handshake; the caller owns the clocking
  -- commitment a grant implies, and grant_sent_o strobes once the
  -- grant's last byte has been latched so the caller can anchor that
  -- commitment. Idle bytes fill the gaps.
  component chunked_link_master_framer is
    generic(
      -- Upper bound, in bytes, of the data the master may have emitted
      -- while a credit frame was in flight from the slave: link
      -- round-trip (in bytes) plus command/response pipeline depth.
      -- Pessimism only under-utilises the link.
      flight_margin_c : natural := 16
      );
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      -- Batch start: emission restarts on a frame boundary. Credit
      -- balance is kept (it is running, per spec).
      batch_start_i : in std_ulogic;

      -- One byte was latched by the transport; advance and present the
      -- next byte.
      byte_ready_i : in  std_ulogic;
      byte_o       : out byte;

      -- Slave RX credit from the deframer (absolute).
      credit_set_i : in  std_ulogic;
      credit_i     : in  unsigned(credit_bits_c-1 downto 0);

      -- TX budget grant to send to the slave. Latched when
      -- grant_valid_i and grant_ready_o coincide; grant_sent_o strobes
      -- the cycle after the frame's last byte is latched by the
      -- transport. On a batch restart a latched, partially-emitted
      -- grant frame is re-emitted from its header.
      grant_i       : in  unsigned(credit_bits_c-1 downto 0);
      grant_valid_i : in  std_ulogic;
      grant_ready_o : out std_ulogic;
      grant_sent_o  : out std_ulogic;

      -- TX stream (payload to send).
      tx_data_i  : in  byte;
      tx_last_i  : in  std_ulogic;
      tx_valid_i : in  std_ulogic;
      tx_ready_o : out std_ulogic;

      -- A chunk is staged and not fully sent yet.
      pending_o : out std_ulogic;
      -- A chunk is staged and the credit balance allows sending part of
      -- it now; tells the batch controller more clocking makes TX
      -- progress.
      sendable_o : out std_ulogic
      );
  end component;

  -- Receive-side decoder for either end. Consumes the byte-aligned
  -- frame stream and splits it:
  --   * data frames  -> data bytes pushed out with last on the frame's end
  --   * credit frames -> credit_o strobe (TX budget on the slave side,
  --                      slave RX credit on the master side)
  --   * tx-level frames -> level_o strobe (master side; a slave ignores it)
  --   * set-pad frames  -> pad_o strobe (transports needing alignment)
  --   * idle/reserved   -> ignored
  -- Flow control is assumed honoured by the sender, so the data sink is
  -- expected to always accept; there is no back-pressure path.
  component chunked_link_deframer is
    port(
      clock_i   : in  std_ulogic;
      reset_n_i : in  std_ulogic;

      byte_i       : in  byte;
      byte_valid_i : in  std_ulogic;

      rx_data_o  : out byte;
      rx_last_o  : out std_ulogic;
      rx_valid_o : out std_ulogic;

      credit_o     : out unsigned(credit_bits_c-1 downto 0);
      credit_set_o : out std_ulogic;
      level_o      : out unsigned(credit_bits_c-1 downto 0);
      level_set_o  : out std_ulogic;
      pad_o        : out std_ulogic_vector(2 downto 0);
      pad_set_o    : out std_ulogic
      );
  end component;

  -- Chunking.
  --
  -- Transports frames (with boundary information) over a pipe (continuous data
  -- stream). Interleaves data with a 2-byte header that contains size-1 and
  -- the EOF information. Max frame size is 2**14 (16 KiB).
  --
  -- Header: [0lnnnnnn nnnnnnnn] (in transmission order, MSB first).
  -- * l: last (active high),
  -- * n: size (MSB first), off by one.
  --
  -- Special values for unchunker's header parser:
  -- * [11--------] (= 0xc0) is a reset marker and does not take another byte
  -- of header
  -- * [10--------] (= 0x80) is a reset release marker.
  --
  -- In the RX path (from chunked pipe to framed), can handle arbitrarily long
  -- frames.
  -- In the TX path (from framed to pipe), it needs a fifo to get the size of
  -- coming chunk before sending. That limits the chunk size (but still allows
  -- to convey arbitrarily long frames).
  --
  -- Typically, on initialization, if peer sends 16KiB+1 byte of 0xc0
  -- to the unchunker, it has the certitude any pending frame has been flushed
  -- and that RX state is synchronized. Then one 0x80 terminates the reset.
  component framed_unchunker is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      in_i : in  nsl_bnoc.pipe.pipe_req_t;
      in_o : out nsl_bnoc.pipe.pipe_ack_t;

      reset_n_o : out std_ulogic;
      
      out_o : out nsl_bnoc.framed.framed_req_t;
      out_i : in nsl_bnoc.framed.framed_ack_t
      );
  end component;

  component framed_chunker is
    generic(
      max_txn_length_l2_c : natural range 2 to 14 := 10
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      in_i : in nsl_bnoc.framed.framed_req_t;
      in_o : out nsl_bnoc.framed.framed_ack_t;

      out_o : out nsl_bnoc.pipe.pipe_req_t;
      out_i : in nsl_bnoc.pipe.pipe_ack_t
      );
  end component;

end package;
