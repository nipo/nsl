library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_sdio;
use nsl_sdio.sdio.all;

-- SD, SDIO and MMC host driven by a command stream, over a pair of
-- AXI stream pipes.
--
-- What travels here is transactions: one command, the answer to it,
-- and the blocks that go with it.  Nothing in the stream knows what a
-- command means, so the command set of a card, its identification
-- sequence and what to do about an error all live on the far end.
-- That is what makes the same fabric serve a card holding memory, an
-- SDIO peripheral and an MMC part, and what makes a card that
-- misbehaves worth pointing this at.
package cbor_transactor is

  -- Responds to CBOR-encoded commands that follow this specification
  -- (CDDL describing valid commands)

  -- A command stream is an array of commands
  -- commands = [* command]

  -- command = nop / delay
  --         / sd-command / sd-read / sd-write / sd-repeat
  --         / set-half-cycle / set-sample-phase / set-width
  --         / set-timeout / set-clock-run / set-events
  --         / lines / info

  -- One byte, answered by nothing, valid wherever a command is.  It
  -- is what a host pads with to put the payload of a write where a
  -- wider stream would rather have it.
  -- nop = undefined

  -- Bus periods to keep clocking for, which is how a card is given
  -- the clocks it wants before it answers anything, and how a poll
  -- loop is paced.
  -- delay = uint

  -- sd-command = #6.0([response, index, argument])
  -- sd-read    = #6.1([response, index, argument, block-size, block-count])
  -- sd-write   = #6.2([response, index, argument, block-size, data])

  -- Runs the commands that follow until the last of them answers
  -- with a payload the predicate accepts, or until the attempts run
  -- out, which fails.  Bodies hold commands without a data phase,
  -- which is what every poll on this bus is made of: the one asking
  -- whether a card is done powering up takes two, the one asking
  -- whether it is done storing a block takes one.
  --
  -- A mask of zero accepts any payload, which leaves the predicate on
  -- the answer alone: that is retry until answered.
  --
  -- A loop is one operation as far as answers go: it answers once,
  -- with what the last command of its last round got, and the
  -- commands of its body answer with nothing.  Otherwise a loop
  -- polling three hundred times would answer three hundred times, or
  -- a host would have to hold a round's worth of answers until it
  -- knew whether the round was the last.
  -- sd-repeat = #6.3([body, attempts, mask, match])

  -- Bus settings, which hold until set again.  Identification runs
  -- slowly over one data line whatever the card, and only a card that
  -- answered says it can do better.
  -- set-half-cycle   = #6.4(uint)   ; fabric cycles in a half period, minus one
  -- set-sample-phase = #6.5(uint)   ; fabric cycle of a period to read at
  -- set-width        = #6.6(1 / 4 / 8)
  -- set-timeout      = #6.7(uint)   ; bus periods a card is given
  -- set-clock-run    = #6.8(bool)   ; whether to clock while idle
  -- set-events       = #6.9(uint)   ; kinds of event to report

  -- lines = #7.1   ; what the wires and the socket look like
  -- info  = #7.2   ; what this host is made of

  -- response    = 0 none / 1 short / 2 short-no-crc / 3 short-busy / 4 long
  -- index       = 0..63
  -- argument    = uint
  -- block-size  = 1..4096
  -- block-count = uint
  -- data        = bstr
  -- body        = 1..4
  -- attempts    = uint
  -- mask        = uint
  -- match       = uint

  -- Only the answers carrying operating conditions have no checksum
  -- worth checking, which is why that is a value of response rather
  -- than a flag of its own: an answer carrying a card register
  -- carries the checksum the card put in it.

  -- The responses are encoded in an array:
  -- responses = [* response-item]

  -- response-item = nop / ack / info-rsp / lines-rsp
  --               / sd-command-rsp / sd-read-rsp / sd-write-rsp
  --               / event

  -- Padding, as in the other direction, and skipped the same way
  -- nop = undefined

  -- ack       = #6.0(null)
  -- info-rsp  = #6.1([version, clock-hz, lane-count, max-block-size])
  -- lines-rsp = #6.2([card-present, cmd, dat, busy])

  -- sd-command-rsp = #6.3([cmd-status, index, payload])
  -- sd-read-rsp    = #6.4([cmd-status, index, payload,
  --                        data, dat-status, blocks])
  -- sd-write-rsp   = #6.5([cmd-status, index, payload,
  --                        dat-status, blocks])

  -- Unsolicited, and only for the kinds set-events asked for.  An
  -- event carries where the thing it reports stands now, not what it
  -- did: what is reported is a level rather than an edge, so a stream
  -- nobody is draining costs latency and never an event.
  --
  -- Events go where they fall: inside the answers of a batch if one
  -- is running, on their own between items if not.  They are never
  -- put inside another item, so nothing has to be pieced back
  -- together.
  -- event = #6.6([event-kind, asserted])

  -- cmd-status = 0 ok / 1 timeout / 2 crc-error / 3 framing-error
  --            / 4 cancelled
  -- dat-status = 0 ok / 1 timeout / 2 crc-error / 3 framing-error
  --            / 4 write-rejected / 5 write-failed / 6 underrun
  --            / 7 cancelled
  -- payload    = bstr .size (0 / 4 / 16)
  -- blocks     = uint
  -- event-kind = 0 card-interrupt / 1 card-inserted / 2 card-removed
  -- asserted   = bool  ; where the kind's own signal stands now
  -- version    = uint  ; of this specification, first so it stays first

  -- The fields of an answer to a read are in the order a host learns
  -- them: what the card said before the data phase opened, then the
  -- blocks, then what became of them.  Data is an indefinite length
  -- byte string holding one chunk per block, so a run that dies on
  -- its third block puts out three chunks and then says why, rather
  -- than having promised a length it cannot reach.

  -- Every command answers with exactly one item, in order, except
  -- nop, which answers with nothing, and the commands of a loop's
  -- body, which the loop answers for.  Events carry their own tag and
  -- are not counted.  A command that fails ends the batch: the items
  -- for the commands that follow it are never put out, so the last
  -- item of a short answer names what failed.  The break closing the
  -- command array is where both ends line up again.

  -- Clearing enable_i drops whatever is running or waiting and
  -- releases the bus.  It is a way out of a wedged bus rather than a
  -- part of using one, and a bus it was used on needs what
  -- nsl_sdio's recovery section describes before it carries anything
  -- again.

  constant cmd_tag_command_c: natural := 0;
  constant cmd_tag_read_c: natural := 1;
  constant cmd_tag_write_c: natural := 2;
  constant cmd_tag_repeat_c: natural := 3;
  constant cmd_tag_half_cycle_c: natural := 4;
  constant cmd_tag_sample_phase_c: natural := 5;
  constant cmd_tag_width_c: natural := 6;
  constant cmd_tag_timeout_c: natural := 7;
  constant cmd_tag_clock_run_c: natural := 8;
  constant cmd_tag_events_c: natural := 9;

  constant cmd_simple_lines_c: natural := 1;
  constant cmd_simple_info_c: natural := 2;

  constant rsp_tag_ack_c: natural := 0;
  constant rsp_tag_info_c: natural := 1;
  constant rsp_tag_lines_c: natural := 2;
  constant rsp_tag_command_c: natural := 3;
  constant rsp_tag_read_c: natural := 4;
  constant rsp_tag_write_c: natural := 5;
  constant rsp_tag_event_c: natural := 6;

  -- Version this specification is at, first field of what info
  -- answers.
  constant spec_version_c: natural := 1;

  component axi4stream_cbor_sdio_transactor is
    generic(
      clock_i_hz_c: natural;
      stream_config_c: nsl_amba.axi4_stream.config_t;
      -- Data lines this host is wired for
      lane_count_c: lane_count_t := 4;
      -- Bytes of a read a host holds on to.  Small enough and this is
      -- a handful of registers, which on some fabrics means a memory
      -- read from an address rather than registers at all; a kilobyte
      -- is a block buffer and lands in a block memory.
      rx_buffer_byte_count_c: positive := 1024
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      -- Cleared, this drops whatever is running or waiting and
      -- releases the bus.  See the recovery a bus needs afterwards.
      enable_i: in std_ulogic := '1';

      sdio_o: out sdio_master_o;
      sdio_i: in sdio_master_i;

      -- Socket contact, for the events that say a card came or went.
      -- It bounces where it comes from, so what arrives here has
      -- settled and is in this clock's domain.
      card_present_i: in std_ulogic := '0';
      -- Set while a card has an interrupt standing.  Nothing drives
      -- this yet: it takes the data engine watching the line a card
      -- signals on, which is what SDIO adds.
      card_interrupt_i: in std_ulogic := '0';

      cmd_i: in nsl_amba.axi4_stream.master_t;
      cmd_o: out nsl_amba.axi4_stream.slave_t;
      rsp_o: out nsl_amba.axi4_stream.master_t;
      rsp_i: in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package cbor_transactor;
