library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;

-- What an SD memory card is, on top of the transactions a host runs:
-- the sequence that brings one from power-up to taking data, and the
-- commands that move blocks.
--
-- Everything here is the command set of a card holding memory.  An
-- SDIO peripheral or an MMC part has its own, over the same host.
package card is

  type card_kind_t is (
    -- Nothing answered
    CARD_NONE,
    -- Standard capacity, addressed by the byte
    CARD_SD,
    -- High capacity, addressed by the block
    CARD_SDHC
    );

  type card_info_t is
  record
    kind: card_kind_t;
    rca: unsigned(15 downto 0);
    -- Whether an address is a block number rather than a byte offset
    block_addressed: boolean;
    -- Blocks of 512 bytes the card holds
    block_count: unsigned(31 downto 0);
    -- Data lines the bus was switched to
    width: bus_width_t;
    cid: std_ulogic_vector(127 downto 0);
    csd: std_ulogic_vector(127 downto 0);
  end record;

  function card_info_none return card_info_t;

  -- Blocks of 512 bytes a card's specific data says it holds, for
  -- both shapes that field has had.
  function csd_block_count(csd: std_ulogic_vector) return unsigned;

  -- Brings a card from power-up to the state where it takes data,
  -- then steps out of the way: transactions from upstream pass
  -- through untouched, and the bus settings it worked out hold.
  --
  -- A step that fails puts the whole sequence back to the start after
  -- a wait, so a card that is not there yet, or one swapped for
  -- another, is picked up whenever it does answer.
  --
  -- The data lines are not touched here, so whoever drives them can
  -- stay wired to the host throughout.
  component card_initializer is
    generic(
      clock_i_hz_c: natural;
      -- Data lines the host is wired for.  A card is widened to four
      -- when there are four.
      lane_count_c: lane_count_t := 4;
      -- Identification runs at 400 kHz at most, whatever the card
      bus_init_hz_c: natural := 400000;
      -- Microseconds of clock before the first command, which covers
      -- both the supply settling and the clocks a card wants before
      -- it answers anything
      power_up_us_c: natural := 5000;
      -- What the bus runs at once a card is identified.  Default
      -- speed is as fast as a card goes without being asked.
      bus_run_hz_c: natural := 25000000
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      -- Starts the sequence over, whatever it was doing
      restart_i: in std_ulogic := '0';

      -- Settings the host runs with, which this owns: identification
      -- happens slowly and over one data line, and only a card that
      -- answered says it can do better.
      half_cycle_m1_o: out unsigned(15 downto 0);
      sample_phase_o: out unsigned(15 downto 0);
      width_o: out bus_width_t;

      info_o: out card_info_t;
      -- Set while info_o describes a card that is ready for data
      ready_o: out std_ulogic;

      -- Transactions from upstream, passed through once a card is
      -- ready
      req_i: in txn_req_t := txn_idle;
      req_o: out txn_ack_t;
      rsp_o: out txn_rsp_t;

      -- Transactions to the host
      host_req_o: out txn_req_t;
      host_req_i: in txn_ack_t;
      host_rsp_i: in txn_rsp_t
      );
  end component;

  -- Bits of a card's status that say something went wrong with what
  -- it was last asked to do.
  constant status_error_mask_c: std_ulogic_vector(31 downto 0)
    := x"fdf90000";
  -- State a card reports while it is ready for another command
  constant status_state_transfer_c: std_ulogic_vector(3 downto 0) := "0100";

  type block_req_t is
  record
    valid: std_ulogic;
    write: std_ulogic;
    -- First block of the run
    lba: unsigned(31 downto 0);
    -- Blocks to move.  Zero moves them for as long as the stream has
    -- something in it and stops on stop_i, which is what dumping to a
    -- card wants.
    count: unsigned(31 downto 0);
  end record;

  type block_ack_t is
  record
    ready: std_ulogic;
  end record;

  type block_status_t is (
    BLOCK_OK,
    -- Card did not answer, or answered something else
    BLOCK_CMD_ERROR,
    -- Blocks did not survive the wires
    BLOCK_DATA_ERROR,
    -- Card would not take what it was given
    BLOCK_WRITE_ERROR,
    -- Fabric side of a write ran dry where the bus could not wait
    BLOCK_UNDERRUN
    );

  type block_rsp_t is
  record
    valid: std_ulogic;
    status: block_status_t;
    -- Blocks that went through whole
    count: unsigned(31 downto 0);
  end record;

  function block_idle return block_req_t;
  function block_read(lba: unsigned; count: natural := 1) return block_req_t;
  function block_write(lba: unsigned; count: natural := 1) return block_req_t;
  function accept(ready: boolean) return block_ack_t;

  -- Blocks in and out of a card, as a run of them at an address.
  --
  -- One request covers a whole run, single or multiple, counted or
  -- not, including the command that ends a run and the wait until the
  -- card is done with what it was given.  What is left for a user is
  -- an address, a direction, and a stream.
  component card_block_device is
    generic(
      -- Times to ask a card whether it is done with what it was given
      -- before giving up on it.  A card is allowed a good fraction of
      -- a second to store a block.
      ready_poll_max_c: natural := 100000
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      info_i: in card_info_t;

      req_i: in block_req_t;
      req_o: out block_ack_t;
      -- Ends a run that was given no count, after the block under way
      stop_i: in std_ulogic := '0';

      rsp_o: out block_rsp_t;

      host_req_o: out txn_req_t;
      host_req_i: in txn_ack_t;
      host_rsp_i: in txn_rsp_t;
      host_stop_o: out std_ulogic
      );
  end component;

end package card;

package body card is

  function card_info_none return card_info_t
  is
  begin
    return card_info_t'(
      kind => CARD_NONE,
      rca => (others => '0'),
      block_addressed => false,
      block_count => (others => '0'),
      width => SDIO_WIDTH_1,
      cid => (others => '0'),
      csd => (others => '0')
      );
  end function;

  function csd_block_count(csd: std_ulogic_vector) return unsigned
  is
    alias c: std_ulogic_vector(127 downto 0) is csd;
    -- Second shape of the structure counts blocks in groups of 1024,
    -- which is all a card holding more than two gigabytes has to say
    -- about its size.
    constant size_v2_c: unsigned(21 downto 0) := unsigned(c(69 downto 48));
    -- The first shape describes the array instead: so many units of
    -- so many blocks of so many bytes.
    constant size_v1_c: unsigned(11 downto 0) := unsigned(c(73 downto 62));
    constant size_mult_c: unsigned(2 downto 0) := unsigned(c(49 downto 47));
    constant read_len_c: unsigned(3 downto 0) := unsigned(c(83 downto 80));
  begin
    if c(127 downto 126) = "00" then
      return shift_left(resize(size_v1_c, 32) + 1,
                        to_integer(size_mult_c + read_len_c) - 7);
    else
      return shift_left(resize(size_v2_c, 32) + 1, 10);
    end if;
  end function;

  function block_idle return block_req_t
  is
  begin
    return block_req_t'(
      valid => '0',
      write => '0',
      lba => (others => '0'),
      count => (others => '0')
      );
  end function;

  function block_read(lba: unsigned; count: natural := 1) return block_req_t
  is
  begin
    return block_req_t'(
      valid => '1',
      write => '0',
      lba => resize(lba, 32),
      count => to_unsigned(count, 32)
      );
  end function;

  function block_write(lba: unsigned; count: natural := 1) return block_req_t
  is
  begin
    return block_req_t'(
      valid => '1',
      write => '1',
      lba => resize(lba, 32),
      count => to_unsigned(count, 32)
      );
  end function;

  function accept(ready: boolean) return block_ack_t
  is
  begin
    if ready then
      return block_ack_t'(ready => '1');
    else
      return block_ack_t'(ready => '0');
    end if;
  end function;

end package body card;
