library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_logic, nsl_sdio;
use nsl_data.crc.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_sdio.sdio.all;

-- Token layer of an SD, SDIO or MMC host: the commands and responses
-- that travel on CMD, and the data blocks that travel on DAT, framed
-- and checked.  Nothing here knows what a command means, which is
-- what makes the layer the same for the three bus flavours.
--
-- Both engines run on the strobes a clock driver issues, one pair per
-- bus clock period.  A host therefore has one clock domain, the bus
-- clock being a divisor of it.
package link is

  -- Checksum of the command line, x^7 + x^3 + 1.  A command token
  -- carries it over the 40 bits that precede it.  A short response
  -- does the same; a long response carries instead the checksum the
  -- card computed over the register it answers with, which covers
  -- only that register's contents.
  --
  -- The bus puts the highest coefficient of a checksum on the wire
  -- first, which is the order crc_spill_vector lays a state out in
  -- for an ascending spill order.
  constant cmd_crc_params_c: crc_params_t := crc_params(
    poly => x"89",
    init => "",
    complement_state => false,
    complement_input => false,
    byte_bit_order => BIT_ORDER_DESCENDING,
    spill_order => EXP_ORDER_ASCENDING,
    byte_order => BYTE_ORDER_INCREASING
    );

  -- Checksum of a data line, x^16 + x^12 + x^5 + 1.  Every line in
  -- use carries its own, computed over the bits that line carried.
  constant dat_crc_params_c: crc_params_t := crc_params(
    poly => x"11021",
    init => "",
    complement_state => false,
    complement_input => false,
    byte_bit_order => BIT_ORDER_DESCENDING,
    spill_order => EXP_ORDER_ASCENDING,
    byte_order => BYTE_ORDER_INCREASING
    );

  type response_kind_t is (
    -- Command a card does not answer
    RESP_NONE,
    -- 48-bit answer
    RESP_SHORT,
    -- 48-bit answer, after which the card holds DAT0 low for as long
    -- as the command keeps it busy
    RESP_SHORT_BUSY,
    -- 136-bit answer, carrying one of the card's registers
    RESP_LONG
    );

  type cmd_req_t is
  record
    valid: std_ulogic;
    index: unsigned(5 downto 0);
    argument: unsigned(31 downto 0);
    response: response_kind_t;
    -- Whether the checksum of the answer means anything.  The answers
    -- that carry an operating conditions register have ones in that
    -- field instead.
    check_crc: boolean;
  end record;

  type cmd_ack_t is
  record
    ready: std_ulogic;
  end record;

  type cmd_status_t is (
    CMD_OK,
    -- No answer started within the window the bus allows
    CMD_TIMEOUT,
    CMD_CRC_ERROR,
    -- Direction or end bit was not what a card's answer has
    CMD_FRAMING_ERROR
    );

  type cmd_rsp_t is
  record
    -- One cycle pulse.  The fields below hold from there until the
    -- next command completes.
    valid: std_ulogic;
    status: cmd_status_t;
    -- The six bits an answer carries after its direction bit: the
    -- index of the command answered, or ones when the answer has no
    -- room for it.
    index: unsigned(5 downto 0);
    -- Argument of a short answer, in the low 32 bits; whole register
    -- of a long one, checksum and trailing one included, which is how
    -- a card numbers its own register bits.
    payload: std_ulogic_vector(127 downto 0);
  end record;

  function cmd_idle return cmd_req_t;
  function cmd_request(index: natural;
                       argument: unsigned;
                       response: response_kind_t;
                       check_crc: boolean := true) return cmd_req_t;
  function accept(ready: boolean) return cmd_ack_t;

  -- Half period, in fabric cycles minus one, of the fastest bus clock
  -- at or below the asked for frequency.
  function half_cycle_m1(clock_i_hz: natural; bus_hz: natural) return natural;

  -- Edge a card answers, which is not the same in every speed mode.
  -- A card clocked at default speed puts what it has on the wires
  -- after the falling edge, so that a host reads it on the rising one
  -- with half a period of margin either side.  High speed moves that
  -- to the rising edge, which is what buys the speed and what costs
  -- the margin.
  type card_output_edge_t is (
    OUTPUT_ON_FALLING,
    OUTPUT_ON_RISING
    );

  -- Fabric cycle of a bus period at whose end a host should capture
  -- what a card drives.  See the sample_phase_i port below for what
  -- the number means.
  --
  -- A card starts driving at most 14 ns after a rising edge and holds
  -- until 2.5 ns past the next one, which leaves a window a little
  -- longer than a bus period, and a host samples at one of the
  -- period's fabric cycle ends.  This picks the candidate closest to
  -- the middle of the window.
  --
  -- The choice is only as good as the fabric clock is fine grained.
  -- Default speed has a whole period of slack and takes any fabric
  -- clock; high speed over a 100 MHz fabric leaves one candidate that
  -- fits, and the hold time alone is what makes it valid.  A fabric
  -- clock four times the bus clock or more leaves a real margin, and
  -- is what the faster modes will want anyway.
  function default_sample_phase(clock_i_hz: natural;
                                half_cycle_m1: natural;
                                edge: card_output_edge_t := OUTPUT_ON_FALLING)
    return natural;

  -- Clock generator of a host: divides the fabric clock down to the
  -- bus clock and tells the engines when to put a bit on the wires
  -- and when to take one off them.
  --
  -- A bus period is 2 * (half_cycle_m1_i + 1) fabric cycles.  The
  -- divisor is an input rather than a generic because it changes
  -- during a card's life: identification happens at 400 kHz, and only
  -- a card that answered says how fast it can be clocked afterwards.
  component link_clock_driver is
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      -- Fabric cycles in a bus clock half period, minus one.  Zero
      -- gives a bus clock at half the fabric clock.
      half_cycle_m1_i: in unsigned;
      -- Fabric cycle of the period at whose end sample_o is issued.
      -- Cycle zero is the one that starts with a rising edge on the
      -- pin, so the cycle numbered k ends k + 1 cycles past that
      -- edge.  Which edge the captured value belongs to depends on
      -- how late in the period the sample lands, and no engine cares:
      -- all they see is one sample per period.
      sample_phase_i: in unsigned;

      -- While cleared, the clock stops low at the end of the period
      -- under way and no strobe is issued until it comes back.  This
      -- is how a host makes a card wait, either to save power or
      -- because a data phase has run dry.
      run_i: in std_ulogic;

      clk_o: out std_ulogic;

      -- Cycle whose end launches the value a card samples on the next
      -- rising edge.  It falls half a period ahead of that edge,
      -- which is the setup a card gets.
      drive_o: out std_ulogic;
      -- Cycle at whose end what a card drives is captured
      sample_o: out std_ulogic;

      -- Set while the clock toggles
      running_o: out std_ulogic
      );
  end component;

  -- Command line of a host: sends a command token, then collects the
  -- answer the request asks for, checksums included.
  --
  -- A request is accepted while req_o.ready is set, and the answer
  -- comes back as a pulse on rsp_o.valid once the card is done with
  -- the command, which for a command that answers with busy means
  -- once it has let go of DAT0.  That wait has no bound here: only a
  -- caller knows how long the command it sent is allowed to take.
  type dat_status_t is (
    DAT_OK,
    -- No block started within the window a card was given
    DAT_TIMEOUT,
    -- What a data line carried does not match the checksum it came
    -- with
    DAT_CRC_ERROR,
    -- A block did not end where a block ends
    DAT_FRAMING_ERROR,
    -- Card says the block it got has a bad checksum
    DAT_WRITE_REJECTED,
    -- Card says it could not store the block it got
    DAT_WRITE_FAILED,
    -- Nothing was there to write when the bus needed it, and a block
    -- under way cannot be held
    DAT_UNDERRUN,
    -- Transfer was taken back before it was through
    DAT_CANCELLED
    );

  type dat_req_t is
  record
    valid: std_ulogic;
    write: std_ulogic;
    -- Bytes in a block, minus one
    block_size_m1: unsigned(11 downto 0);
    -- Blocks to transfer.  Zero runs until stop_i, which is how a
    -- host streams for as long as it has something to stream.
    block_count: unsigned(31 downto 0);
  end record;

  type dat_ack_t is
  record
    ready: std_ulogic;
  end record;

  type dat_rsp_t is
  record
    -- One cycle pulse.  The fields below hold from there until the
    -- next transfer ends.
    valid: std_ulogic;
    status: dat_status_t;
    -- Blocks that went through whole
    block_count: unsigned(31 downto 0);
  end record;

  function dat_idle return dat_req_t;
  function dat_request(write: boolean;
                       block_size: positive := 512;
                       block_count: natural := 1) return dat_req_t;
  function accept(ready: boolean) return dat_ack_t;

  component link_cmd_engine is
    generic(
      -- Bus periods a card may take before starting its answer.  The
      -- bus allows 64.
      response_timeout_cycle_c: natural := 64
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      drive_i: in std_ulogic;
      sample_i: in std_ulogic;

      cmd_o: out nsl_io.io.tristated;
      cmd_i: in std_ulogic;
      -- DAT0, where a card signals it is still working
      dat0_i: in std_ulogic;

      req_i: in cmd_req_t;
      req_o: out cmd_ack_t;

      rsp_o: out cmd_rsp_t;
      -- Set while a card holds DAT0 low after its answer
      busy_o: out std_ulogic
      );
  end component;

  -- Data lines of a host: moves whole blocks, framed and checksummed,
  -- over as many lines as the bus was switched to.
  --
  -- A block cannot be held once it starts: a card clocks its side of
  -- it out whatever the host does with it.  So a write takes its
  -- first byte before starting a block and then demands the rest as
  -- the bus asks for them, and a read hands bytes over without
  -- asking.  Whoever sits on those ports has to be able to keep up
  -- for a whole block, which in practice means buffering one.
  component link_dat_engine is
    generic(
      -- Data lines this host is wired for.  A transfer over more of
      -- them than that is a design error, not a runtime one.
      lane_count_c: lane_count_t := 4
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      drive_i: in std_ulogic;
      sample_i: in std_ulogic;

      d_o: out nsl_io.io.tristated_vector(max_lane_count_c - 1 downto 0);
      d_i: in std_ulogic_vector(max_lane_count_c - 1 downto 0);

      -- Data lines the bus was switched to.  A card is identified on
      -- one line and only widened afterwards, so this changes during
      -- a card's life, but never while a transfer is under way.
      width_i: in bus_width_t;

      -- Bus periods a card is given to start a block, to report what
      -- it made of one, and to store it
      timeout_cycle_i: in unsigned;

      req_i: in dat_req_t;
      req_o: out dat_ack_t;
      -- Finish the block under way, then stop.  Only a transfer with
      -- no block count pays attention to it.
      stop_i: in std_ulogic := '0';
      -- Drop the transfer where it stands, wherever that is.  What
      -- the card was in the middle of is the caller's problem.
      cancel_i: in std_ulogic := '0';

      rsp_o: out dat_rsp_t;
      -- Set while a card holds DAT0 low over a block it is storing
      busy_o: out std_ulogic;

      -- Bytes to write
      tx_valid_i: in std_ulogic;
      tx_data_i: in byte;
      tx_ready_o: out std_ulogic;

      -- Bytes read, which nobody may refuse
      rx_valid_o: out std_ulogic;
      rx_data_o: out byte;
      -- Whether what a read hands over can still be taken.  Clearing
      -- it holds the bus, but only from the end of the period under
      -- way, so it has to go once there is room for just one more
      -- byte.
      rx_room_i: in std_ulogic := '1';

      -- Set while the engine is inside a block with nothing to write
      -- or nowhere to put what it reads.  A host stops the bus clock
      -- on this, which is the only way to hold a card mid block.
      stall_o: out std_ulogic
      );
  end component;

end package link;

package body link is

  function cmd_idle return cmd_req_t
  is
  begin
    return cmd_req_t'(
      valid => '0',
      index => (others => '0'),
      argument => (others => '0'),
      response => RESP_NONE,
      check_crc => true
      );
  end function;

  function cmd_request(index: natural;
                       argument: unsigned;
                       response: response_kind_t;
                       check_crc: boolean := true) return cmd_req_t
  is
  begin
    return cmd_req_t'(
      valid => '1',
      index => to_unsigned(index, 6),
      argument => resize(argument, 32),
      response => response,
      check_crc => check_crc
      );
  end function;

  function accept(ready: boolean) return cmd_ack_t
  is
  begin
    if ready then
      return cmd_ack_t'(ready => '1');
    else
      return cmd_ack_t'(ready => '0');
    end if;
  end function;

  function dat_idle return dat_req_t
  is
  begin
    return dat_req_t'(
      valid => '0',
      write => '0',
      block_size_m1 => (others => '0'),
      block_count => (others => '0')
      );
  end function;

  function dat_request(write: boolean;
                       block_size: positive := 512;
                       block_count: natural := 1) return dat_req_t
  is
  begin
    return dat_req_t'(
      valid => '1',
      write => to_logic(write),
      block_size_m1 => to_unsigned(block_size - 1, 12),
      block_count => to_unsigned(block_count, 32)
      );
  end function;

  function accept(ready: boolean) return dat_ack_t
  is
  begin
    if ready then
      return dat_ack_t'(ready => '1');
    else
      return dat_ack_t'(ready => '0');
    end if;
  end function;

  function half_cycle_m1(clock_i_hz: natural; bus_hz: natural) return natural
  is
    -- Rounded up, as a bus clock may be slower than asked for but
    -- never faster.
    constant half_cycle_c: natural
      := (clock_i_hz + 2 * bus_hz - 1) / (2 * bus_hz);
  begin
    if half_cycle_c = 0 then
      return 0;
    else
      return half_cycle_c - 1;
    end if;
  end function;

  function default_sample_phase(clock_i_hz: natural;
                                half_cycle_m1: natural;
                                edge: card_output_edge_t := OUTPUT_ON_FALLING)
    return natural
  is
    -- Worst delay a card takes to answer the edge it answers, and the
    -- shortest time it holds that value past the next one.
    constant card_output_delay_ps_c: natural := 14000;
    constant card_output_hold_ps_c: natural := 2500;

    constant cycle_ps_c: natural := 1000000000 / (clock_i_hz / 1000);
    constant period_cycle_c: natural := 2 * (half_cycle_m1 + 1);
    constant period_ps_c: natural := period_cycle_c * cycle_ps_c;

    -- Times below are counted from the edge a card answers.  What it
    -- drove there stands until it answers the next one.
    constant valid_from_ps_c: natural := card_output_delay_ps_c;
    constant valid_to_ps_c: natural := period_ps_c + card_output_hold_ps_c;
    constant middle_ps_c: natural := (valid_from_ps_c + valid_to_ps_c) / 2;

    -- Cycles between the edge a card answered and the end of phase
    -- zero.  Phase zero opens with a rising edge, so a card answering
    -- that same edge is one cycle behind, while one answering the
    -- falling edge that came before is a low half period plus that
    -- cycle behind.
    function phase_zero_cycle_count return natural
    is
    begin
      case edge is
        when OUTPUT_ON_RISING => return 1;
        when OUTPUT_ON_FALLING => return half_cycle_m1 + 2;
      end case;
    end function;

    constant offset_c: natural := phase_zero_cycle_count;

    -- A point beyond the end of a period is the same point of the
    -- next one, which is why the answer wraps rather than saturates:
    -- a host takes one sample per period whatever happens, and which
    -- edge a sample belongs to is nothing any engine can tell.
    -- Signed on purpose: a fabric clock barely faster than the bus
    -- lands before phase zero, and a point before a period opens is
    -- the same point of the one before it.
    constant candidate_c: integer
      := ((middle_ps_c + cycle_ps_c / 2) / cycle_ps_c) - offset_c;
    constant phase_c: natural := candidate_c mod period_cycle_c;

    -- Where that lands, brought back into the period the window
    -- opens in.  A host samples once a period whatever happens, so
    -- what matters is whether any of those moments falls in the
    -- window, and they are a period apart in both directions.
    function sample_ps return natural
    is
      variable ret: natural := (offset_c + phase_c) * cycle_ps_c;
    begin
      while ret >= valid_from_ps_c + period_ps_c
      loop
        ret := ret - period_ps_c;
      end loop;

      while ret < valid_from_ps_c
      loop
        ret := ret + period_ps_c;
      end loop;

      return ret;
    end function;
  begin
    assert sample_ps <= valid_to_ps_c
      report "No fabric cycle of a bus period ends where a card's "
      & "output is steady"
      severity failure;

    return phase_c;
  end function;

end package body link;
