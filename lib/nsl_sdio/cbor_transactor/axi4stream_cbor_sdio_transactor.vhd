library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.cbor.all;
use nsl_logic.bool.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;
use nsl_sdio.cbor_transactor.all;

entity axi4stream_cbor_sdio_transactor is
  generic(
    clock_i_hz_c: natural;
    stream_config_c: nsl_amba.axi4_stream.config_t;
    lane_count_c: lane_count_t := 4;
    -- Bytes of a read a host holds on to.  Small enough and this is a
    -- handful of registers, which on some fabrics means a memory read
    -- from an address rather than registers at all; a kilobyte is a
    -- block buffer and lands in a block memory.
    rx_buffer_byte_count_c: positive := 1024
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    enable_i: in std_ulogic := '1';

    sdio_o: out sdio_master_o;
    sdio_i: in sdio_master_i;

    card_present_i: in std_ulogic := '0';
    card_interrupt_i: in std_ulogic := '0';

    cmd_i: in nsl_amba.axi4_stream.master_t;
    cmd_o: out nsl_amba.axi4_stream.slave_t;
    rsp_o: out nsl_amba.axi4_stream.master_t;
    rsp_i: in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of axi4stream_cbor_sdio_transactor is

  constant block_size_max_c: natural := 4096;

  -- Longest run of bytes put out in one go, which is what the whole
  -- of an answer to info takes.
  constant emit_byte_count_c: natural := 16;
  constant emit_cfg_c: nsl_amba.axi4_stream.buffer_config_t
    := nsl_amba.axi4_stream.buffer_config(stream_config_c, emit_byte_count_c);

  -- Items of one byte, spelled out rather than built, as they are
  -- what the encoding is made of.
  constant item_false_c: byte := x"f4";
  constant item_true_c: byte := x"f5";

  constant null_item_c: byte_string(0 to 0) := (0 => x"f6");
  constant break_item_c: byte_string(0 to 0) := (0 => x"ff");
  constant array_indefinite_item_c: byte_string(0 to 0) := (0 => x"9f");
  constant bstr_indefinite_item_c: byte_string(0 to 0) := (0 => x"5f");

  -- Item headers of a size the argument's width settles, rather than
  -- the shortest the value would fit in: what goes out has to be a
  -- known length before the value is known.
  function cbor_u5(v: unsigned) return byte_string
  is
    variable ret: byte_string(0 to 0);
  begin
    ret(0) := std_ulogic_vector(resize(v, 8));

    return ret;
  end function;

  function cbor_u8(v: unsigned) return byte_string
  is
    variable ret: byte_string(0 to 1);
  begin
    ret(0) := x"18";
    ret(1) := std_ulogic_vector(resize(v, 8));

    return ret;
  end function;

  function cbor_u16(v: unsigned) return byte_string
  is
    variable w: unsigned(15 downto 0) := resize(v, 16);
    variable ret: byte_string(0 to 2);
  begin
    ret(0) := x"19";
    ret(1) := std_ulogic_vector(w(15 downto 8));
    ret(2) := std_ulogic_vector(w(7 downto 0));

    return ret;
  end function;

  function cbor_u32(v: unsigned) return byte_string
  is
    variable w: unsigned(31 downto 0) := resize(v, 32);
    variable ret: byte_string(0 to 4);
  begin
    ret(0) := x"1a";
    ret(1) := std_ulogic_vector(w(31 downto 24));
    ret(2) := std_ulogic_vector(w(23 downto 16));
    ret(3) := std_ulogic_vector(w(15 downto 8));
    ret(4) := std_ulogic_vector(w(7 downto 0));

    return ret;
  end function;

  function cbor_bool(v: boolean) return byte_string
  is
    variable ret: byte_string(0 to 0);
  begin
    if v then
      ret(0) := item_true_c;
    else
      ret(0) := item_false_c;
    end if;

    return ret;
  end function;

  -- What this host is made of never changes, so its answer is built
  -- once and for all.
  constant info_rsp_c: byte_string
    := cbor_tag_hdr(rsp_tag_info_c)
    & cbor_array_hdr(length => 4)
    & cbor_positive(spec_version_c)
    & cbor_positive(clock_i_hz_c)
    & cbor_positive(lane_count_c)
    & cbor_positive(block_size_max_c);

  constant ack_rsp_c: byte_string
    := cbor_tag_hdr(rsp_tag_ack_c) & null_item_c;

  -- Bytes a card register takes in an answer, which is what the kind
  -- of answer asked for says.
  function payload_byte_count(response: response_kind_t) return natural
  is
  begin
    case response is
      when RESP_NONE => return 0;
      when RESP_LONG => return 16;
      when others => return 4;
    end case;
  end function;

  type state_t is (
    ST_RESET,

    -- The array holding a batch
    ST_BATCH_GET,
    ST_BATCH_ENTER,
    ST_BATCH_END,

    -- One command of it
    ST_ITEM_GET,
    ST_ITEM_EXEC,
    -- What a tag applies to
    ST_ARG_GET,
    ST_ARG_EXEC,
    -- Elements of what a tag applies to
    ST_FIELD_GET,
    ST_FIELD_EXEC,

    ST_DELAY,

    -- Blocks a write carries, worked out from the bytes it carries
    ST_WRITE_BLOCKS,

    ST_TXN_START,
    ST_CMD_WAIT,
    -- What a loop answers with, once it knows which round was the
    -- last
    ST_EMIT_COMMAND,
    ST_REPEAT_LOAD,
    ST_WRITE_DATA,
    ST_READ_WAIT,
    ST_READ_DATA,
    ST_TXN_WAIT,

    ST_EMIT,
    ST_EMIT_PAYLOAD,
    ST_READ_OPEN,

    -- What is left of a batch whose commands will not be run
    ST_DRAIN
    );

  type op_t is (
    OP_NONE,
    OP_COMMAND,
    OP_READ,
    OP_WRITE,
    OP_HALF_CYCLE,
    OP_SAMPLE_PHASE,
    OP_WIDTH,
    OP_TIMEOUT,
    OP_CLOCK_RUN,
    OP_EVENTS,
    OP_REPEAT
    );

  -- A command of a loop's body, kept until the loop is through with
  -- it.  Bodies hold no data phase, so this is all there is to one.
  constant step_max_c: natural := 4;

  type loop_step_t is
  record
    response: response_kind_t;
    check_crc: boolean;
    index: unsigned(5 downto 0);
    argument: unsigned(31 downto 0);
  end record;

  type loop_step_vector is array (natural range <>) of loop_step_t;

  type event_kind_t is (
    EVENT_INTERRUPT,
    EVENT_INSERTED,
    EVENT_REMOVED
    );

  -- Which way a socket went is what says which kind a change is, and
  -- so which bit of the mask it answers to.
  function present_event_kind(present: std_ulogic) return event_kind_t
  is
  begin
    if present = '1' then
      return EVENT_INSERTED;
    else
      return EVENT_REMOVED;
    end if;
  end function;

  function present_event_enabled(mask: unsigned;
                                 present: std_ulogic) return std_ulogic
  is
  begin
    return mask(event_kind_t'pos(present_event_kind(present)));
  end function;

  -- One event, as it goes out
  function event_item(kind: event_kind_t; asserted: std_ulogic)
    return byte_string
  is
    variable ret: byte_string(0 to 3);
  begin
    ret(0 to 0) := cbor_tag_hdr(rsp_tag_event_c);
    ret(1 to 1) := cbor_array_hdr(length => 2);
    ret(2) := std_ulogic_vector(to_unsigned(event_kind_t'pos(kind), 8));
    if asserted = '1' then
      ret(3) := item_true_c;
    else
      ret(3) := item_false_c;
    end if;

    return ret;
  end function;

  type regs_t is
  record
    state: state_t;
    -- Where to go once what is being put out is through
    emit_ret: state_t;

    parser: parser_t;
    -- Commands left in a batch, and whether it said how many
    batch_left: natural range 0 to 65535;
    batch_indefinite: boolean;

    op: op_t;
    field: natural range 0 to 7;
    field_count: natural range 0 to 7;

    -- What a transaction is made of
    response: response_kind_t;
    check_crc: boolean;
    index: unsigned(5 downto 0);
    argument: unsigned(31 downto 0);
    block_size: unsigned(12 downto 0);
    block_count: unsigned(31 downto 0);
    -- Bytes of the write payload still to hand over
    data_left: unsigned(31 downto 0);
    -- The byte the data lines are to take next, and whether it is
    -- there.  An engine inside a block cannot wait for one to arrive:
    -- all it can do is stop the clock until it has, so one is kept
    -- standing by, out of a register rather than off the stream.
    tx_byte: byte;
    tx_full: boolean;
    -- Bytes of the block being put out
    chunk_left: unsigned(12 downto 0);
    -- Bytes of an item's contents to go by without reading them
    drain_left: unsigned(31 downto 0);
    txn_done: boolean;

    -- What the bus runs with
    half_cycle_m1: unsigned(15 downto 0);
    sample_phase: unsigned(15 downto 0);
    width: bus_width_t;
    timeout: unsigned(23 downto 0);
    clock_run: std_ulogic;
    events: unsigned(7 downto 0);

    delay: unsigned(31 downto 0);

    -- Bytes of a write still to go through, and what is left over of
    -- the ones already counted.  A block count is a division, and a
    -- division is a bit at a time: doing it in one go puts a chain of
    -- subtractions between two registers, which is what holds a
    -- fabric clock down.
    div_num: unsigned(31 downto 0);
    div_rem: unsigned(12 downto 0);
    div_left: natural range 0 to 32;

    emit: nsl_amba.axi4_stream.buffer_t;
    payload_left: natural range 0 to 16;
    -- Where to go once a card register has been put out
    after_payload: state_t;
    last: boolean;

    -- A loop, and where it stands
    step: loop_step_vector(0 to step_max_c - 1);
    step_count: natural range 0 to step_max_c;
    slot: natural range 0 to step_max_c - 1;
    attempts: unsigned(15 downto 0);
    mask: unsigned(31 downto 0);
    match: unsigned(31 downto 0);
    -- Whether what is running is a body command, whose answer the
    -- loop keeps to itself
    quiet: boolean;
    capturing: boolean;

    -- Whether a batch is being read, so that an event knows whether
    -- it lands among answers or on its own
    parser_busy: boolean;

    -- What the two lines an event reports were last said to be, and
    -- whether either has moved since
    present: std_ulogic;
    interrupt: std_ulogic;
    present_changed: boolean;
    interrupt_changed: boolean;
  end record;

  signal r, rin: regs_t;

  signal txn_req_s: txn_req_t;
  signal txn_ack_s: txn_ack_t;
  signal txn_rsp_s: txn_rsp_t;

  signal tx_valid_s, tx_ready_s: std_ulogic;
  signal tx_data_s: byte;
  signal rx_valid_s, rx_ready_s: std_ulogic;
  signal rx_data_s: byte;

  signal delay_tick_s: std_ulogic;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, enable_i, txn_ack_s, txn_rsp_s,
                      rx_valid_s, rx_data_s, tx_ready_s, delay_tick_s,
                      card_present_i, sdio_i) is
    variable tag: natural;
    variable value: unsigned(31 downto 0);
    -- What is left over of a write's byte count, with the next bit of
    -- it brought down beside it
    variable step_v: unsigned(12 downto 0);

    -- Puts a run of bytes out, then goes on with what follows it
    procedure emit(data: byte_string; ret: state_t) is
    begin
      rin.emit <= nsl_amba.axi4_stream.reset(emit_cfg_c, data);
      rin.emit_ret <= ret;
      rin.state <= ST_EMIT;
    end procedure;

    -- A command that fails takes the rest of a batch with it
    procedure give_up is
    begin
      rin.state <= ST_DRAIN;
      rin.parser <= reset;
      rin.drain_left <= (others => '0');
      rin.quiet <= false;
      rin.capturing <= false;
    end procedure;

  begin
    rin <= r;

    step_v := r.div_rem(r.div_rem'left - 1 downto 0) & r.div_num(r.div_num'left);

    -- Tags and simple values are small; what an item carries is not,
    -- and a whole word of it does not fit in an integer.
    tag := to_integer(arg(r.parser, 8));
    value := arg(r.parser, 32);

    -- A transaction is through long before what it answers with has
    -- been put out, so what says so is caught wherever it lands.
    if txn_rsp_s.valid = '1' then
      rin.txn_done <= true;
    end if;

    -- What an event reports is a level, and what is remembered is
    -- that it moved.  A line that goes and comes back while nothing
    -- is draining still says so, and says where it stands now, which
    -- is all a host needs to know it has to look again.
    if card_present_i /= r.present then
      rin.present <= card_present_i;
      rin.present_changed <= true;
    end if;

    if card_interrupt_i /= r.interrupt then
      rin.interrupt <= card_interrupt_i;
      rin.interrupt_changed <= true;
    end if;

    -- A kind nobody asked for is not kept waiting
    if r.present_changed and present_event_enabled(r.events, r.present) = '0'
    then
      rin.present_changed <= false;
    end if;

    if r.interrupt_changed and r.events(event_kind_t'pos(EVENT_INTERRUPT)) = '0'
    then
      rin.interrupt_changed <= false;
    end if;

    case r.state is
      when ST_RESET =>
        rin.parser <= reset;
        rin.half_cycle_m1 <= to_unsigned(half_cycle_m1(clock_i_hz_c, 400000), 16);
        rin.sample_phase <= to_unsigned(
          default_sample_phase(clock_i_hz_c,
                               half_cycle_m1(clock_i_hz_c, 400000)), 16);
        rin.width <= SDIO_WIDTH_1;
        rin.timeout <= to_unsigned(65535, 24);
        rin.clock_run <= '1';
        rin.events <= (others => '0');
        rin.last <= false;
        rin.capturing <= false;
        rin.quiet <= false;
        rin.parser_busy <= false;
        rin.present <= card_present_i;
        rin.interrupt <= card_interrupt_i;
        rin.present_changed <= false;
        rin.interrupt_changed <= false;
        rin.state <= ST_BATCH_GET;

      when ST_BATCH_GET =>
        if r.present_changed or r.interrupt_changed then
          if not r.parser_busy then
            -- Nothing is being read, so this goes out on its own
            rin.last <= true;
            if r.present_changed then
              rin.present_changed <= false;
              emit(event_item(present_event_kind(r.present), r.present),
                   ST_BATCH_GET);
            else
              rin.interrupt_changed <= false;
              emit(event_item(EVENT_INTERRUPT, r.interrupt), ST_BATCH_GET);
            end if;
          end if;
        elsif nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          rin.parser <= feed(r.parser, cmd_i.data(0));
          rin.parser_busy <= true;
          if is_last(r.parser, cmd_i.data(0)) then
            rin.parser_busy <= false;
            rin.state <= ST_BATCH_ENTER;
          end if;
        end if;

      when ST_BATCH_ENTER =>
        rin.parser <= reset;

        if kind(r.parser) = KIND_ARRAY then
          rin.last <= false;
          rin.batch_indefinite <= r.parser.indefinite;
          if r.parser.indefinite then
            rin.batch_left <= 0;
          else
            rin.batch_left <= to_integer(arg(r.parser, 16));
          end if;

          -- A batch is answered by an array of its own, opened before
          -- anything is known of what is in it.
          emit(array_indefinite_item_c, ST_ITEM_GET);
        else
          give_up;
        end if;

      when ST_ITEM_GET =>
        if (r.present_changed or r.interrupt_changed) and not r.parser_busy
        then
          -- Between the answers of a batch, which is where an event
          -- belongs while one is running
          if r.present_changed then
            rin.present_changed <= false;
            emit(event_item(present_event_kind(r.present), r.present),
                 ST_ITEM_GET);
          else
            rin.interrupt_changed <= false;
            emit(event_item(EVENT_INTERRUPT, r.interrupt), ST_ITEM_GET);
          end if;
        elsif not r.batch_indefinite and r.batch_left = 0 then
          rin.state <= ST_BATCH_END;
        elsif nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          rin.parser <= feed(r.parser, cmd_i.data(0));
          rin.parser_busy <= true;
          if is_last(r.parser, cmd_i.data(0)) then
            rin.parser_busy <= false;
            rin.state <= ST_ITEM_EXEC;
          end if;
        end if;

      when ST_ITEM_EXEC =>
        rin.parser <= reset;
        rin.op <= OP_NONE;

        if not r.batch_indefinite then
          rin.batch_left <= r.batch_left - 1;
        end if;

        case kind(r.parser) is
          when KIND_BREAK =>
            rin.state <= ST_BATCH_END;

          when KIND_UNDEFINED =>
            -- Padding, answered by nothing
            rin.state <= ST_ITEM_GET;

          when KIND_POSITIVE =>
            -- Bus periods to keep clocking for
            rin.delay <= value;
            rin.state <= ST_DELAY;

          when KIND_SIMPLE =>
            case tag is
              when cmd_simple_lines_c =>
                emit(cbor_tag_hdr(rsp_tag_lines_c)
                     & cbor_array_hdr(length => 4)
                     & cbor_bool(card_present_i = '1')
                     & cbor_bool(sdio_i.cmd = '1')
                     & cbor_u8(unsigned(sdio_i.d))
                     & cbor_bool(sdio_i.d(0) = '0'),
                     ST_ITEM_GET);

              when cmd_simple_info_c =>
                emit(info_rsp_c, ST_ITEM_GET);

              when others =>
                give_up;
            end case;

          when KIND_TAG =>
            rin.state <= ST_ARG_GET;

            -- A loop holds commands and nothing else: what its body
            -- is made of has to be over before the loop can run, and
            -- a data phase is not.
            if r.capturing and tag /= cmd_tag_command_c then
              give_up;
            end if;

            case tag is
              when cmd_tag_command_c =>
                rin.op <= OP_COMMAND;
                rin.field_count <= 3;

              when cmd_tag_read_c =>
                rin.op <= OP_READ;
                rin.field_count <= 5;

              when cmd_tag_write_c =>
                rin.op <= OP_WRITE;
                rin.field_count <= 5;

              when cmd_tag_half_cycle_c =>
                rin.op <= OP_HALF_CYCLE;

              when cmd_tag_sample_phase_c =>
                rin.op <= OP_SAMPLE_PHASE;

              when cmd_tag_width_c =>
                rin.op <= OP_WIDTH;

              when cmd_tag_timeout_c =>
                rin.op <= OP_TIMEOUT;

              when cmd_tag_clock_run_c =>
                rin.op <= OP_CLOCK_RUN;

              when cmd_tag_events_c =>
                rin.op <= OP_EVENTS;

              when cmd_tag_repeat_c =>
                rin.op <= OP_REPEAT;
                rin.field_count <= 4;

              when others =>
                give_up;
            end case;

          when others =>
            give_up;
        end case;

      when ST_ARG_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          rin.parser <= feed(r.parser, cmd_i.data(0));
          rin.parser_busy <= true;
          if is_last(r.parser, cmd_i.data(0)) then
            rin.parser_busy <= false;
            rin.state <= ST_ARG_EXEC;
          end if;
        end if;

      when ST_ARG_EXEC =>
        rin.parser <= reset;
        rin.field <= 0;

        case r.op is
          when OP_COMMAND | OP_READ | OP_WRITE | OP_REPEAT =>
            if kind(r.parser) = KIND_ARRAY
              and to_integer(arg(r.parser, 16)) = r.field_count
            then
              rin.state <= ST_FIELD_GET;
            else
              give_up;
            end if;

          when OP_HALF_CYCLE =>
            rin.half_cycle_m1 <= resize(value, 16);
            emit(ack_rsp_c, ST_ITEM_GET);

          when OP_SAMPLE_PHASE =>
            rin.sample_phase <= resize(value, 16);
            emit(ack_rsp_c, ST_ITEM_GET);

          when OP_WIDTH =>
            case to_integer(value) is
              when 1 => rin.width <= SDIO_WIDTH_1;
              when 4 => rin.width <= SDIO_WIDTH_4;
              when others => rin.width <= SDIO_WIDTH_8;
            end case;
            emit(ack_rsp_c, ST_ITEM_GET);

          when OP_TIMEOUT =>
            rin.timeout <= resize(value, 24);
            emit(ack_rsp_c, ST_ITEM_GET);

          when OP_CLOCK_RUN =>
            rin.clock_run <= to_logic(kind(r.parser) = KIND_TRUE);
            emit(ack_rsp_c, ST_ITEM_GET);

          when OP_EVENTS =>
            rin.events <= resize(value, 8);
            emit(ack_rsp_c, ST_ITEM_GET);

          when others =>
            give_up;
        end case;

      when ST_FIELD_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          rin.parser <= feed(r.parser, cmd_i.data(0));
          rin.parser_busy <= true;
          if is_last(r.parser, cmd_i.data(0)) then
            rin.parser_busy <= false;
            rin.state <= ST_FIELD_EXEC;
          end if;
        end if;

      when ST_FIELD_EXEC =>
        rin.parser <= reset;
        rin.field <= r.field + 1;
        rin.state <= ST_FIELD_GET;

        if r.op = OP_REPEAT then
          case r.field is
            when 0 =>
              if value = 0 or value > step_max_c then
                give_up;
              else
                rin.step_count <= to_integer(value);
              end if;

            when 1 =>
              rin.attempts <= resize(value, 16);

            when 2 =>
              rin.mask <= value;

            when others =>
              rin.match <= value;
              -- What follows is the body, kept rather than run
              rin.capturing <= true;
              rin.slot <= 0;
              rin.state <= ST_ITEM_GET;
          end case;
        else
        case r.field is
          when 0 =>
            -- What kind of answer to expect, and whether its checksum
            -- means anything
            rin.check_crc <= true;
            case to_integer(value) is
              when 0 => rin.response <= RESP_NONE;
              when 1 => rin.response <= RESP_SHORT;
              when 2 =>
                rin.response <= RESP_SHORT;
                rin.check_crc <= false;
              when 3 => rin.response <= RESP_SHORT_BUSY;
              when others => rin.response <= RESP_LONG;
            end case;

          when 1 =>
            rin.index <= resize(value, 6);

          when 2 =>
            rin.argument <= value;
            if r.op = OP_COMMAND then
              if r.capturing then
                -- One more of a loop's body put away
                rin.step(r.slot).response <= r.response;
                rin.step(r.slot).check_crc <= r.check_crc;
                rin.step(r.slot).index <= r.index;
                rin.step(r.slot).argument <= value;

                if r.slot = r.step_count - 1 then
                  rin.capturing <= false;
                  rin.quiet <= true;
                  rin.slot <= 0;
                  rin.state <= ST_REPEAT_LOAD;
                else
                  rin.slot <= r.slot + 1;
                  rin.state <= ST_ITEM_GET;
                end if;
              else
                rin.state <= ST_TXN_START;
              end if;
            end if;

          when 3 =>
            rin.block_size <= resize(value, 13);

          when others =>
            case r.op is
              when OP_READ =>
                rin.block_count <= value;
                rin.state <= ST_TXN_START;

              when others =>
                -- Blocks of a write are however many the bytes make
                if kind(r.parser) = KIND_BSTR and not r.parser.indefinite then
                  rin.data_left <= value;
                  rin.div_num <= value;
                  rin.div_rem <= (others => '0');
                  rin.div_left <= value'length;
                  rin.block_count <= (others => '0');
                  rin.state <= ST_WRITE_BLOCKS;
                else
                  give_up;
                end if;
            end case;
        end case;
        end if;

      when ST_DELAY =>
        -- Clocking with nothing on the wires is what a card is given
        -- before it answers anything.
        if r.delay = 0 then
          emit(ack_rsp_c, ST_ITEM_GET);
        elsif delay_tick_s = '1' then
          rin.delay <= r.delay - 1;
        end if;

      when ST_WRITE_BLOCKS =>
        -- One bit of the count per cycle: what is left over so far
        -- takes the next bit of it, and a block comes out of it
        -- whenever there is room for one.
        if r.div_left = 0 then
          rin.state <= ST_TXN_START;
        else
          rin.div_num <= r.div_num(r.div_num'left - 1 downto 0) & '0';
          rin.div_left <= r.div_left - 1;

          if step_v >= r.block_size then
            rin.div_rem <= step_v - r.block_size;
            rin.block_count <= r.block_count(r.block_count'left - 1 downto 0)
                               & '1';
          else
            rin.div_rem <= step_v;
            rin.block_count <= r.block_count(r.block_count'left - 1 downto 0)
                               & '0';
          end if;
        end if;

      when ST_TXN_START =>
        rin.txn_done <= false;
        if txn_ack_s.ready = '1' then
          rin.state <= ST_CMD_WAIT;
        end if;

      when ST_REPEAT_LOAD =>
        -- One command of the body, as it was put away
        rin.op <= OP_COMMAND;
        rin.response <= r.step(r.slot).response;
        rin.check_crc <= r.step(r.slot).check_crc;
        rin.index <= r.step(r.slot).index;
        rin.argument <= r.step(r.slot).argument;
        rin.state <= ST_TXN_START;

      when ST_EMIT_COMMAND =>
        -- What a loop answers with, which is what its last command
        -- got in its last round.
        rin.payload_left <= payload_byte_count(r.response);
        emit(cbor_tag_hdr(rsp_tag_command_c)
             & cbor_array_hdr(length => 3)
             & cbor_u5(to_unsigned(cmd_status_t'pos(txn_rsp_s.cmd_status), 8))
             & cbor_u8(txn_rsp_s.index)
             & cbor_bstr_hdr(length => to_unsigned(payload_byte_count(r.response), 8)),
             ST_EMIT_PAYLOAD);

      when ST_CMD_WAIT =>
        -- What a card says about a transfer comes before the blocks
        -- of it, which is the order it is put out in.
        if r.quiet then
          -- A body command answers to its loop, not to the stream
          if txn_rsp_s.valid = '1' or r.txn_done then
            rin.state <= ST_TXN_WAIT;
          end if;
        elsif txn_rsp_s.cmd_valid = '1' or txn_rsp_s.valid = '1' then
          rin.payload_left <= payload_byte_count(r.response);

          case r.op is
            when OP_COMMAND =>
              rin.after_payload <= ST_TXN_WAIT;
              emit(cbor_tag_hdr(rsp_tag_command_c)
                   & cbor_array_hdr(length => 3)
                   & cbor_u5(to_unsigned(cmd_status_t'pos(txn_rsp_s.cmd_status), 8))
                   & cbor_u8(txn_rsp_s.index)
                   & cbor_bstr_hdr(length => to_unsigned(payload_byte_count(r.response), 8)),
                   ST_EMIT_PAYLOAD);

            when OP_READ =>
              rin.after_payload <= ST_READ_OPEN;
              emit(cbor_tag_hdr(rsp_tag_read_c)
                   & cbor_array_hdr(length => 6)
                   & cbor_u5(to_unsigned(cmd_status_t'pos(txn_rsp_s.cmd_status), 8))
                   & cbor_u8(txn_rsp_s.index)
                   & cbor_bstr_hdr(length => to_unsigned(payload_byte_count(r.response), 8)),
                   ST_EMIT_PAYLOAD);

            when others =>
              rin.tx_full <= false;
              rin.after_payload <= ST_WRITE_DATA;
              emit(cbor_tag_hdr(rsp_tag_write_c)
                   & cbor_array_hdr(length => 5)
                   & cbor_u5(to_unsigned(cmd_status_t'pos(txn_rsp_s.cmd_status), 8))
                   & cbor_u8(txn_rsp_s.index)
                   & cbor_bstr_hdr(length => to_unsigned(payload_byte_count(r.response), 8)),
                   ST_EMIT_PAYLOAD);
          end case;
        end if;

      when ST_WRITE_DATA =>
        -- What the data lines took leaves room for the next byte,
        -- and the stream fills it again.  Nothing here reaches the
        -- stream from the engine in the same cycle: what the engine
        -- is offered comes out of a register, and so does whether the
        -- stream is being taken from.
        if r.tx_full and tx_ready_s = '1' then
          rin.tx_full <= false;
        end if;

        if not r.tx_full and r.data_left /= 0
          and nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i)
        then
          rin.tx_byte <= cmd_i.data(0);
          rin.tx_full <= true;
          rin.data_left <= r.data_left - 1;
        end if;

        if r.data_left = 0 and not r.tx_full then
          rin.state <= ST_TXN_WAIT;
        end if;

      when ST_READ_WAIT =>
        -- A block that never started gets no chunk of its own, which
        -- is what keeps a chunk's length a promise that holds.
        if rx_valid_s = '1' then
          rin.chunk_left <= r.block_size;
          emit(cbor_bstr_hdr(length => r.block_size(11 downto 0)), ST_READ_DATA);
        elsif r.txn_done then
          emit(break_item_c, ST_TXN_WAIT);
        end if;

      when ST_READ_DATA =>
        if r.chunk_left = 0 then
          rin.state <= ST_READ_WAIT;
        elsif rx_valid_s = '1'
          and nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i)
        then
          rin.chunk_left <= r.chunk_left - 1;
        end if;

      when ST_TXN_WAIT =>
        if r.txn_done and r.quiet then
          if r.slot /= r.step_count - 1 then
            rin.slot <= r.slot + 1;
            rin.state <= ST_REPEAT_LOAD;
          elsif txn_rsp_s.cmd_status = CMD_OK
            and (unsigned(txn_rsp_s.payload(31 downto 0)) and r.mask) = r.match
          then
            -- The loop got what it was waiting for
            rin.quiet <= false;
            rin.after_payload <= ST_ITEM_GET;
            rin.state <= ST_EMIT_COMMAND;
          elsif r.attempts <= 1 then
            -- It never will, and a batch does not go on past that
            rin.quiet <= false;
            rin.drain_left <= (others => '0');
            rin.after_payload <= ST_DRAIN;
            rin.state <= ST_EMIT_COMMAND;
          else
            rin.attempts <= r.attempts - 1;
            rin.slot <= 0;
            rin.state <= ST_REPEAT_LOAD;
          end if;
        elsif r.txn_done then
          case r.op is
            when OP_COMMAND =>
              if txn_rsp_s.cmd_status = CMD_OK then
                rin.state <= ST_ITEM_GET;
              else
                give_up;
              end if;

            when others =>
              emit(cbor_u5(to_unsigned(dat_status_t'pos(txn_rsp_s.dat_status), 8))
                   & cbor_u32(txn_rsp_s.block_count),
                   ST_ITEM_GET);

              if txn_rsp_s.cmd_status /= CMD_OK
                or txn_rsp_s.dat_status /= DAT_OK
              then
                rin.emit_ret <= ST_DRAIN;
              end if;
          end case;
        end if;

      when ST_EMIT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(emit_cfg_c, r.emit) then
            rin.state <= r.emit_ret;
          end if;
          rin.emit <= nsl_amba.axi4_stream.shift(emit_cfg_c, r.emit);
        end if;

      when ST_EMIT_PAYLOAD =>
        -- What follows a card register is whatever the operation
        -- carrying it has left to do.
        if r.payload_left = 0 then
          rin.state <= r.after_payload;
        elsif nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          rin.payload_left <= r.payload_left - 1;
        end if;

      when ST_READ_OPEN =>
        -- Blocks go out as chunks of one byte string whose length is
        -- not promised, as how many there will be is not known until
        -- they stop coming.
        emit(bstr_indefinite_item_c, ST_READ_WAIT);

      when ST_DRAIN =>
        -- What is left of a batch goes by without being run, item by
        -- item, up to the break that closes it.  What an item holds
        -- goes by as well, which is what makes a command stream
        -- something that can be walked without being understood.
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          if r.drain_left /= 0 then
            rin.drain_left <= r.drain_left - 1;
          else
            rin.parser <= feed(r.parser, cmd_i.data(0));

            if is_last(r.parser, cmd_i.data(0)) then
              rin.parser <= reset;

              case kind(feed(r.parser, cmd_i.data(0))) is
                when KIND_BREAK =>
                  rin.state <= ST_BATCH_END;

                when KIND_BSTR | KIND_TSTR =>
                  rin.drain_left <= arg(feed(r.parser, cmd_i.data(0)), 32);

                when others =>
                  null;
              end case;
            end if;
          end if;
        end if;

      when ST_BATCH_END =>
        -- What the bus was set to outlives a batch; only where the
        -- stream stands is started over.
        rin.last <= true;
        rin.parser <= reset;
        emit(break_item_c, ST_BATCH_GET);
    end case;

    if enable_i = '0' then
      rin.state <= ST_RESET;
    end if;
  end process;

  -- What goes out is either something built here, a card register, or
  -- the blocks themselves.
  stream: process(r, rx_valid_s, rx_data_s, txn_rsp_s, cmd_i, rsp_i,
                  tx_ready_s) is
    variable payload: byte_string(0 to 15);
  begin
    rsp_o <= nsl_amba.axi4_stream.transfer_defaults(stream_config_c);
    cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, false);
    rx_ready_s <= '0';
    tx_valid_s <= '0';
    tx_data_s <= x"00";

    for i in payload'range
    loop
      payload(i) := txn_rsp_s.payload(127 - 8 * i downto 120 - 8 * i);
    end loop;

    case r.state is
      when ST_BATCH_GET | ST_ITEM_GET | ST_ARG_GET | ST_FIELD_GET
        | ST_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);

      when ST_EMIT =>
        rsp_o <= nsl_amba.axi4_stream.next_beat(
          cfg => emit_cfg_c, b => r.emit,
          last => r.last and nsl_amba.axi4_stream.is_last(emit_cfg_c, r.emit));

      when ST_EMIT_PAYLOAD =>
        if r.payload_left /= 0 then
          rsp_o <= nsl_amba.axi4_stream.transfer(
            stream_config_c,
            bytes => (0 => payload(16 - r.payload_left)),
            valid => true);
        end if;

      when ST_WRITE_DATA =>
        tx_valid_s <= to_logic(r.tx_full);
        tx_data_s <= r.tx_byte;

        if not r.tx_full and r.data_left /= 0 then
          cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);
        end if;

      when ST_READ_DATA =>
        if r.chunk_left /= 0 then
          rsp_o <= nsl_amba.axi4_stream.transfer(
            stream_config_c,
            bytes => (0 => rx_data_s),
            valid => rx_valid_s = '1');
          rx_ready_s <= to_logic(
            nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i));
        end if;

      when others =>
        null;
    end case;
  end process;

  request: process(r) is
  begin
    txn_req_s <= txn_idle;

    if r.state = ST_TXN_START then
      txn_req_s.valid <= '1';
      txn_req_s.index <= r.index;
      txn_req_s.argument <= r.argument;
      txn_req_s.response <= r.response;
      txn_req_s.check_crc <= r.check_crc;
      txn_req_s.block_size_m1 <= resize(r.block_size - 1, 12);
      txn_req_s.block_count <= r.block_count;

      case r.op is
        when OP_READ =>
          txn_req_s.data <= DATA_READ;

        when OP_WRITE =>
          txn_req_s.data <= DATA_WRITE;

        when others =>
          txn_req_s.data <= DATA_NONE;
      end case;
    end if;
  end process;

  -- Bus periods, for the times a card is given clocks rather than
  -- commands.
  ticker: nsl_sdio.link.link_clock_driver
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      half_cycle_m1_i => r.half_cycle_m1,
      sample_phase_i => r.sample_phase,
      run_i => '1',

      clk_o => open,
      drive_o => delay_tick_s,
      sample_o => open,
      running_o => open
      );

  host: nsl_sdio.host.host_controller
    generic map(
      lane_count_c => lane_count_c,
      rx_buffer_byte_count_c => rx_buffer_byte_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sdio_o => sdio_o,
      sdio_i => sdio_i,

      half_cycle_m1_i => r.half_cycle_m1,
      sample_phase_i => r.sample_phase,
      width_i => r.width,
      timeout_cycle_i => r.timeout,
      clock_run_i => r.clock_run,

      req_i => txn_req_s,
      req_o => txn_ack_s,

      rsp_o => txn_rsp_s,

      tx_valid_i => tx_valid_s,
      tx_data_i => tx_data_s,
      tx_ready_o => tx_ready_s,

      rx_valid_o => rx_valid_s,
      rx_data_o => rx_data_s,
      rx_ready_i => rx_ready_s
      );

end architecture;
