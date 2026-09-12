library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;

-- A whole host, and the transaction it runs: one command, the answer
-- to it, and the blocks that go with it.
--
-- A data phase is not a thing of its own on this bus.  It belongs to
-- the command that opened it, and the two have to be set going in an
-- order that depends on which way the data goes: a card sends of its
-- own accord as soon as it has answered a read, while it only starts
-- looking for a written block once it has answered the write.  That
-- order is what this layer is for, and it is the same whether the
-- card holds memory, an SDIO peripheral or an MMC part.
--
-- What a transaction means is not: the command set, the
-- identification sequence and what to do about an error all belong
-- above this.
package host is

  type data_dir_t is (
    DATA_NONE,
    DATA_READ,
    DATA_WRITE
    );

  type txn_req_t is
  record
    valid: std_ulogic;
    index: unsigned(5 downto 0);
    argument: unsigned(31 downto 0);
    response: response_kind_t;
    -- Whether the checksum of the answer means anything
    check_crc: boolean;

    data: data_dir_t;
    -- Bytes in a block, minus one
    block_size_m1: unsigned(11 downto 0);
    -- Blocks the data phase carries.  Zero streams for as long as
    -- there is something to stream, and stops on stop_i.
    block_count: unsigned(31 downto 0);
  end record;

  type txn_ack_t is
  record
    ready: std_ulogic;
  end record;

  type txn_rsp_t is
  record
    -- One cycle pulse, when the card has answered the command but
    -- before any blocks have moved.  What a card says about a
    -- transfer it is about to do is worth having while it does it,
    -- and a user streaming blocks out has nowhere to put it later.
    cmd_valid: std_ulogic;
    -- One cycle pulse, when the whole transaction is through.  The
    -- fields below hold from there until the next one ends.
    valid: std_ulogic;
    cmd_status: cmd_status_t;
    -- Left at DAT_OK by a transaction with no data phase
    dat_status: dat_status_t;
    index: unsigned(5 downto 0);
    payload: std_ulogic_vector(127 downto 0);
    -- Blocks that went through whole
    block_count: unsigned(31 downto 0);
  end record;

  -- cmd_status, index and payload hold from cmd_valid onwards;
  -- dat_status and block_count from valid onwards.

  function txn_idle return txn_req_t;
  function txn_command(index: natural;
                       argument: unsigned;
                       response: response_kind_t;
                       check_crc: boolean := true) return txn_req_t;
  function txn_read(index: natural;
                    argument: unsigned;
                    block_size: positive := 512;
                    block_count: natural := 1) return txn_req_t;
  function txn_write(index: natural;
                     argument: unsigned;
                     block_size: positive := 512;
                     block_count: natural := 1) return txn_req_t;
  function accept(ready: boolean) return txn_ack_t;

  -- Everything that talks to the wires: the clock, both engines, and
  -- what sequences them.
  --
  -- A block cannot be held once it starts, so a host that runs out of
  -- data to write, or out of room for what it reads, stops the bus
  -- clock until it has some again.  That is what a card holding
  -- memory allows, and it saves the block of buffering a host would
  -- otherwise need on either side.
  component host_controller is
    generic(
      -- Data lines this host is wired for
      lane_count_c: lane_count_t := 4;
      -- Bytes of slack on the read side.  Clock gating only takes
      -- effect from the end of the period under way, so a couple of
      -- bytes are all this needs.
      rx_buffer_byte_count_c: positive := 8
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      sdio_o: out sdio_master_o;
      sdio_i: in sdio_master_i;

      -- Fabric cycles in a bus clock half period, minus one
      half_cycle_m1_i: in unsigned;
      -- Where in a bus period to capture what a card drives.  See
      -- default_sample_phase in nsl_sdio.link.
      sample_phase_i: in unsigned;
      -- Data lines the bus was switched to
      width_i: in bus_width_t;
      -- Bus periods a card is given to answer with data, or to store
      -- what it was given
      timeout_cycle_i: in unsigned;
      -- Keeps the bus clocked while no transaction is under way,
      -- which a card needs to power up and to work through what it
      -- was last told to do.
      clock_run_i: in std_ulogic := '1';

      req_i: in txn_req_t;
      req_o: out txn_ack_t;
      -- Ends a data phase that was given no block count, after the
      -- block under way
      stop_i: in std_ulogic := '0';

      rsp_o: out txn_rsp_t;

      -- Bytes to write.  A block keeps asking until it is through,
      -- and holds the bus rather than give up when nothing comes.
      tx_valid_i: in std_ulogic := '0';
      tx_data_i: in byte := x"00";
      tx_ready_o: out std_ulogic;

      -- Bytes read
      rx_valid_o: out std_ulogic;
      rx_data_o: out byte;
      rx_ready_i: in std_ulogic := '1'
      );
  end component;

end package host;

package body host is

  function txn_idle return txn_req_t
  is
  begin
    return txn_req_t'(
      valid => '0',
      index => (others => '0'),
      argument => (others => '0'),
      response => RESP_NONE,
      check_crc => true,
      data => DATA_NONE,
      block_size_m1 => (others => '0'),
      block_count => (others => '0')
      );
  end function;

  function txn_command(index: natural;
                       argument: unsigned;
                       response: response_kind_t;
                       check_crc: boolean := true) return txn_req_t
  is
    variable ret: txn_req_t := txn_idle;
  begin
    ret.valid := '1';
    ret.index := to_unsigned(index, 6);
    ret.argument := resize(argument, 32);
    ret.response := response;
    ret.check_crc := check_crc;

    return ret;
  end function;

  function txn_read(index: natural;
                    argument: unsigned;
                    block_size: positive := 512;
                    block_count: natural := 1) return txn_req_t
  is
    variable ret: txn_req_t := txn_command(index, argument, RESP_SHORT);
  begin
    ret.data := DATA_READ;
    ret.block_size_m1 := to_unsigned(block_size - 1, 12);
    ret.block_count := to_unsigned(block_count, 32);

    return ret;
  end function;

  function txn_write(index: natural;
                     argument: unsigned;
                     block_size: positive := 512;
                     block_count: natural := 1) return txn_req_t
  is
    variable ret: txn_req_t := txn_command(index, argument, RESP_SHORT);
  begin
    ret.data := DATA_WRITE;
    ret.block_size_m1 := to_unsigned(block_size - 1, 12);
    ret.block_count := to_unsigned(block_count, 32);

    return ret;
  end function;

  function accept(ready: boolean) return txn_ack_t
  is
  begin
    if ready then
      return txn_ack_t'(ready => '1');
    else
      return txn_ack_t'(ready => '0');
    end if;
  end function;

end package body host;
