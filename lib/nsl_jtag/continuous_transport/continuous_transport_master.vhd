library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_bnoc, nsl_data, nsl_math, nsl_memory;
use nsl_data.bytestream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.chunked_link.all;
use nsl_jtag.transactor.all;
use nsl_jtag.continuous_transport.all;

-- Host-side master for continuous_transport, driving a framed_ate.
--
-- Exchanges chunked_link frames with a continuous_transport_slave TAP by
-- issuing framed_ate command frames. Each command frame is one complete batch,
-- self-contained so it can be interleaved with frames from other transactors
-- sharing the same ATE: it assumes Run-Test/Idle, selects the instruction
-- (Capture-IR, then pre padding ones, the IR value, post padding ones), opens
-- the data register (Capture-DR), streams the batch body as write+read byte
-- shifts, and returns to Run-Test/Idle. The very first batch after reset is
-- prefixed with a Test-Logic-Reset sequence, which also hard-resets the
-- slave transport.
--
-- The TDO stream is bit-hunted with the regular deserializer, so neither the
-- chain geometry nor the alignment pad mechanism is needed on this end: any
-- upstream/downstream BYPASS offset is absorbed by the SOF search. All
-- geometry- and pipeline-dependent timing is folded into flight_margin_c.
--
-- Batch policy: a batch opens when there is work (local TX pending, or the
-- slave advertised a non-empty backlog) or when the poll backoff expires;
-- enable_i gates batch opening only, never cuts a running batch. One budget
-- grant is issued per batch, sized from rx_room_i (derated), the slave's last
-- known backlog and the batch size bound; the batch keeps clocking until the
-- grant commitment is honoured, local TX can no longer progress, and a minimum
-- length letting slave control frames fly back has elapsed.
--
-- rx_room_i is the free space, in bytes, of whatever receives rx_o; the sink
-- is expected to always accept (grants never exceed the advertised room).
-- Config inputs (IR value and lengths) are sampled when a batch opens.
entity continuous_transport_master is
  generic(
    ir_len_max_c : positive;
    ir_pre_max_c : natural := 8;
    ir_post_max_c : natural := 8;
    -- Upper bound, in bytes, of the link round-trip: upstream + downstream
    -- BYPASS bits, ATE command/response pipeline, TAP internal latency.
    -- Pessimism only costs a little extra clocking per batch.
    flight_margin_c : natural := 16;
    -- Bound on the data bytes clocked in one batch body.
    batch_bytes_max_c : positive := 1024;
    -- Budget granted to an apparently-idle slave, so freshly queued data
    -- can flow without waiting for a backlog advertisement round-trip.
    idle_grant_c : positive := 16;
    backoff_width_c : positive := 16;
    -- TCK divisor programmed into the ATE in the first batch's prologue.
    divisor_m1_c : natural range 0 to 255 := 0
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    -- Gates opening of new batches; a running batch always completes.
    enable_i : in std_ulogic := '1';
    -- Cycles between the end of a batch and the next unsolicited polling
    -- batch. Work (TX data, known slave backlog) opens a batch immediately.
    poll_backoff_i : in unsigned(backoff_width_c-1 downto 0) := (others => '0');

    -- Instruction register selection for the target TAP.
    ir_i : in std_ulogic_vector(ir_len_max_c-1 downto 0);
    ir_len_m1_i : in integer range 0 to ir_len_max_c-1;
    -- BYPASS instruction bits shifted before/after the IR value for the
    -- other devices of the chain.
    ir_pre_len_i : in integer range 0 to ir_pre_max_c := 0;
    ir_post_len_i : in integer range 0 to ir_post_max_c := 0;

    -- framed_ate command/response pair.
    cmd_o : out nsl_bnoc.framed.framed_req_t;
    cmd_i : in  nsl_bnoc.framed.framed_ack_t;
    rsp_i : in  nsl_bnoc.framed.framed_req_t;
    rsp_o : out nsl_bnoc.framed.framed_ack_t;

    -- Payload to the remote TAP.
    tx_i : in  nsl_bnoc.framed.framed_req_t;
    tx_o : out nsl_bnoc.framed.framed_ack_t;

    -- Payload from the remote TAP; the sink must always accept.
    rx_o : out nsl_bnoc.framed.framed_req_t;
    rx_i : in  nsl_bnoc.framed.framed_ack_t;
    -- Free space downstream of rx_o, bounding budget grants.
    rx_room_i : in unsigned(credit_bits_c-1 downto 0)
    );
end entity;

architecture beh of continuous_transport_master is

  -- Data bytes per write+read shift command (framed_ate maximum).
  constant dr_chunk_c : integer := 32;
  -- Bytes possibly received but not yet reflected in rx_room_i
  -- (deserializer, deframer, sink input registers).
  constant rx_pipe_margin_c : integer := 8;
  -- Minimum batch body, letting the slave's first control frames complete
  -- the round trip before the close decision.
  constant body_min_c : integer := flight_margin_c + dr_chunk_c + 8;
  -- Grant bound keeping grant + margins within the batch size bound.
  constant grant_max_c : integer := batch_bytes_max_c - 2*flight_margin_c - 2*dr_chunk_c;

  constant ir_w_c : integer := nsl_math.arith.max(8, ir_len_max_c);
  constant ir_left_max_c : integer := nsl_math.arith.max(
    ir_len_max_c, nsl_math.arith.max(ir_pre_max_c, ir_post_max_c));

  -- Response accounting token, one per issued command.
  constant token_data_bit_c : natural := 7;    -- command returns data bytes
  constant token_capture_bit_c : natural := 6; -- command is the batch's Capture-DR
  -- bits 4..0: data byte count - 1

  type cmd_state_t is (
    CMD_RESET,
    CMD_IDLE,
    CMD_DIV,
    CMD_DIV_VAL,
    CMD_TLR,
    CMD_TLR_RTI,
    CMD_IR_CAP,
    CMD_IR_OP,
    CMD_IR_DATA,
    CMD_DR_CAP,
    CMD_BODY_DECIDE,
    CMD_BODY_OP,
    CMD_BODY_DATA,
    CMD_RUN
    );

  type ir_phase_t is (
    PH_PRE,
    PH_IR,
    PH_POST
    );

  type rsp_state_t is (
    RSP_TOKEN,
    RSP_DATA_GET,
    RSP_UNPACK,
    RSP_STATUS
    );

  type regs_t is
  record
    cmd_state : cmd_state_t;
    tap_virgin : boolean;
    ir_shreg : std_ulogic_vector(ir_w_c-1 downto 0);
    ir_phase : ir_phase_t;
    ir_left : integer range 0 to ir_left_max_c;
    chunk_bits_m1 : integer range 0 to 7;
    body_left_m1 : integer range 0 to dr_chunk_c-1;
    preamble_left : integer range 0 to preamble_min_c;
    sof_pending : boolean;
    bytes_done : integer range 0 to batch_bytes_max_c + dr_chunk_c;
    body_min_left : integer range 0 to body_min_c;
    commit_left : integer range 0 to batch_bytes_max_c;
    grant_pending : std_ulogic;
    grant_outstanding : std_ulogic;
    grant_value : unsigned(credit_bits_c-1 downto 0);
    level_known : unsigned(credit_bits_c-1 downto 0);
    backoff : unsigned(backoff_width_c-1 downto 0);

    rsp_state : rsp_state_t;
    rsp_data_left : integer range 0 to dr_chunk_c-1;
    rsp_bit_left : integer range 0 to 7;
    rsp_shreg : byte;
    rsp_capture : std_ulogic;
  end record;

  signal r, rin : regs_t;

  -- Framer side.
  signal framer_byte_s : byte;
  signal framer_byte_ready_s : std_ulogic;
  signal framer_batch_start_s : std_ulogic;
  signal grant_ready_s, grant_sent_s : std_ulogic;
  signal pending_s, sendable_s : std_ulogic;

  -- Deserializer / deframer side.
  signal des_shift_s, des_capture_s, des_tdi_s : std_ulogic;
  signal des_byte_s : byte;
  signal des_byte_valid_s : std_ulogic;
  signal credit_s : unsigned(credit_bits_c-1 downto 0);
  signal credit_set_s : std_ulogic;
  signal level_s : unsigned(credit_bits_c-1 downto 0);
  signal level_set_s : std_ulogic;
  signal rx_data_s : byte;
  signal rx_last_s, rx_valid_s : std_ulogic;

  -- Token fifo.
  signal tok_in_data, tok_out_data : std_ulogic_vector(7 downto 0);
  signal tok_in_valid, tok_in_ready : std_ulogic;
  signal tok_out_valid, tok_out_ready : std_ulogic;

begin

  assert grant_max_c > 0
    report "batch_bytes_max_c too small for flight_margin_c"
    severity failure;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_TOKEN;
      r.rsp_capture <= '0';
    end if;
  end process;

  transition: process(r, enable_i, poll_backoff_i,
                      ir_i, ir_len_m1_i, ir_pre_len_i, ir_post_len_i,
                      cmd_i, rsp_i, tx_i, rx_room_i,
                      grant_ready_s, grant_sent_s, pending_s, sendable_s,
                      level_s, level_set_s, rx_valid_s,
                      tok_in_ready, tok_out_valid, tok_out_data)
    variable chunk_n : integer range 1 to 8;
    variable grant_room, grant_v : integer;
  begin
    rin <= r;
    rin.rsp_capture <= '0';

    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;
        rin.tap_virgin <= true;
        rin.grant_pending <= '0';
        rin.grant_outstanding <= '0';
        rin.level_known <= (others => '0');
        rin.backoff <= (others => '0');

      when CMD_IDLE =>
        if r.backoff /= 0 then
          rin.backoff <= r.backoff - 1;
        end if;
        if enable_i = '1'
          and (pending_s = '1' or tx_i.valid = '1'
               or r.level_known /= 0 or r.backoff = 0) then
          rin.preamble_left <= preamble_min_c;
          rin.sof_pending <= true;
          rin.bytes_done <= 0;
          rin.body_min_left <= body_min_c;
          rin.commit_left <= 0;
          if r.tap_virgin then
            rin.cmd_state <= CMD_DIV;
          else
            rin.cmd_state <= CMD_IR_CAP;
          end if;
        end if;

      when CMD_DIV =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.cmd_state <= CMD_DIV_VAL;
        end if;

      when CMD_DIV_VAL =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_TLR;
        end if;

      when CMD_TLR =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.cmd_state <= CMD_TLR_RTI;
        end if;

      when CMD_TLR_RTI =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.tap_virgin <= false;
          rin.cmd_state <= CMD_IR_CAP;
        end if;

      when CMD_IR_CAP =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.ir_shreg <= (others => '1');
          rin.ir_shreg(ir_len_max_c-1 downto 0) <= ir_i;
          if ir_pre_len_i /= 0 then
            rin.ir_phase <= PH_PRE;
            rin.ir_left <= ir_pre_len_i;
          else
            rin.ir_phase <= PH_IR;
            rin.ir_left <= ir_len_m1_i + 1;
          end if;
          rin.cmd_state <= CMD_IR_OP;
        end if;

      when CMD_IR_OP =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.chunk_bits_m1 <= nsl_math.arith.min(8, r.ir_left) - 1;
          rin.cmd_state <= CMD_IR_DATA;
        end if;

      when CMD_IR_DATA =>
        if cmd_i.ready = '1' then
          chunk_n := r.chunk_bits_m1 + 1;
          if r.ir_phase = PH_IR then
            rin.ir_shreg <= std_ulogic_vector(
              shift_right(unsigned(r.ir_shreg), chunk_n));
          end if;
          if r.ir_left = chunk_n then
            case r.ir_phase is
              when PH_PRE =>
                rin.ir_phase <= PH_IR;
                rin.ir_left <= ir_len_m1_i + 1;
                rin.cmd_state <= CMD_IR_OP;

              when PH_IR =>
                if ir_post_len_i /= 0 then
                  rin.ir_phase <= PH_POST;
                  rin.ir_left <= ir_post_len_i;
                  rin.cmd_state <= CMD_IR_OP;
                else
                  rin.cmd_state <= CMD_DR_CAP;
                end if;

              when PH_POST =>
                rin.cmd_state <= CMD_DR_CAP;
            end case;
          else
            rin.ir_left <= r.ir_left - chunk_n;
            rin.cmd_state <= CMD_IR_OP;
          end if;
        end if;

      when CMD_DR_CAP =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          -- One grant per batch, decided here: bounded by the advertised
          -- room (derated by the receive pipeline), by what the slave is
          -- believed to hold (with a floor for freshly queued data), and by
          -- the batch size bound.
          grant_room := 0;
          if rx_room_i > rx_pipe_margin_c then
            grant_room := to_integer(rx_room_i) - rx_pipe_margin_c;
          end if;
          grant_v := nsl_math.arith.min(
            grant_room,
            nsl_math.arith.min(
              nsl_math.arith.max(to_integer(r.level_known), idle_grant_c),
              grant_max_c));
          if grant_v > 0 then
            rin.grant_pending <= '1';
            rin.grant_value <= to_unsigned(grant_v, credit_bits_c);
          end if;
          rin.cmd_state <= CMD_BODY_DECIDE;
        end if;

      when CMD_BODY_DECIDE =>
        -- Keep the batch going while the grant commitment is unmet, a grant
        -- frame is still in flight, the minimum body has not elapsed, or
        -- local TX can make progress within the batch size bound.
        if r.body_min_left > 0
          or r.commit_left > 0
          or r.grant_pending = '1'
          or r.grant_outstanding = '1'
          or (sendable_s = '1' and r.bytes_done < batch_bytes_max_c) then
          rin.cmd_state <= CMD_BODY_OP;
        else
          rin.cmd_state <= CMD_RUN;
        end if;

      when CMD_BODY_OP =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.body_left_m1 <= dr_chunk_c - 1;
          rin.cmd_state <= CMD_BODY_DATA;
        end if;

      when CMD_BODY_DATA =>
        if cmd_i.ready = '1' then
          rin.bytes_done <= r.bytes_done + 1;
          if r.body_min_left /= 0 then
            rin.body_min_left <= r.body_min_left - 1;
          end if;
          if r.commit_left /= 0 then
            rin.commit_left <= r.commit_left - 1;
          end if;
          if r.preamble_left /= 0 then
            rin.preamble_left <= r.preamble_left - 1;
          elsif r.sof_pending then
            rin.sof_pending <= false;
          end if;
          if r.body_left_m1 = 0 then
            rin.cmd_state <= CMD_BODY_DECIDE;
          else
            rin.body_left_m1 <= r.body_left_m1 - 1;
          end if;
        end if;

      when CMD_RUN =>
        if cmd_i.ready = '1' and tok_in_ready = '1' then
          rin.backoff <= poll_backoff_i;
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    -- Grant handshake with the framer.
    if r.grant_pending = '1' and grant_ready_s = '1' then
      rin.grant_pending <= '0';
      rin.grant_outstanding <= '1';
    end if;
    if grant_sent_s = '1' then
      rin.grant_outstanding <= '0';
      rin.commit_left <= to_integer(r.grant_value) + flight_margin_c;
    end if;

    -- Slave backlog estimate: absolute on each tx-level frame, decremented
    -- per received data byte in between.
    if level_set_s = '1' then
      rin.level_known <= level_s;
    elsif rx_valid_s = '1' and r.level_known /= 0 then
      rin.level_known <= r.level_known - 1;
    end if;

    -- Response side.
    case r.rsp_state is
      when RSP_TOKEN =>
        if tok_out_valid = '1' then
          if tok_out_data(token_capture_bit_c) = '1' then
            rin.rsp_capture <= '1';
          end if;
          if tok_out_data(token_data_bit_c) = '1' then
            rin.rsp_data_left <= to_integer(unsigned(tok_out_data(4 downto 0)));
            rin.rsp_state <= RSP_DATA_GET;
          else
            rin.rsp_state <= RSP_STATUS;
          end if;
        end if;

      when RSP_DATA_GET =>
        if rsp_i.valid = '1' then
          rin.rsp_shreg <= rsp_i.data;
          rin.rsp_bit_left <= 7;
          rin.rsp_state <= RSP_UNPACK;
        end if;

      when RSP_UNPACK =>
        rin.rsp_shreg <= '0' & r.rsp_shreg(7 downto 1);
        if r.rsp_bit_left = 0 then
          if r.rsp_data_left = 0 then
            rin.rsp_state <= RSP_STATUS;
          else
            rin.rsp_data_left <= r.rsp_data_left - 1;
            rin.rsp_state <= RSP_DATA_GET;
          end if;
        else
          rin.rsp_bit_left <= r.rsp_bit_left - 1;
        end if;

      when RSP_STATUS =>
        if rsp_i.valid = '1' then
          assert rsp_i.data = x"5a" or rsp_i.data = x"5b"
            report "Unexpected framed_ate status byte"
            severity warning;
          rin.rsp_state <= RSP_TOKEN;
        end if;
    end case;
  end process;

  moore: process(r, framer_byte_s, tok_in_ready)
  begin
    cmd_o <= framed_req_idle_c;
    tok_in_data <= (others => '0');

    case r.cmd_state is
      when CMD_RESET | CMD_IDLE | CMD_BODY_DECIDE =>
        null;

      when CMD_DIV =>
        cmd_o <= framed_flit(JTAG_CMD_DIVISOR, last => false,
                             valid => tok_in_ready = '1');

      when CMD_DIV_VAL =>
        cmd_o <= framed_flit(std_ulogic_vector(to_unsigned(divisor_m1_c, 8)),
                             last => false);

      when CMD_TLR =>
        -- 8 Test-Logic-Reset cycles.
        cmd_o <= framed_flit(x"b0", last => false, valid => tok_in_ready = '1');

      when CMD_TLR_RTI | CMD_RUN =>
        -- One Run-Test/Idle cycle; ends the frame when closing the batch.
        cmd_o <= framed_flit(x"90", last => r.cmd_state = CMD_RUN,
                             valid => tok_in_ready = '1');

      when CMD_IR_CAP =>
        cmd_o <= framed_flit(JTAG_CMD_IR_CAPTURE, last => false,
                             valid => tok_in_ready = '1');

      when CMD_IR_OP =>
        -- Shift bits, write only.
        cmd_o <= framed_flit(
          std_ulogic_vector(to_unsigned(16#f0# + nsl_math.arith.min(8, r.ir_left) - 1, 8)),
          last => false, valid => tok_in_ready = '1');

      when CMD_IR_DATA =>
        if r.ir_phase = PH_IR then
          cmd_o <= framed_flit(r.ir_shreg(7 downto 0), last => false);
        else
          cmd_o <= framed_flit(x"ff", last => false);
        end if;

      when CMD_DR_CAP =>
        cmd_o <= framed_flit(JTAG_CMD_DR_CAPTURE, last => false,
                             valid => tok_in_ready = '1');
        tok_in_data(token_capture_bit_c) <= '1';

      when CMD_BODY_OP =>
        -- Shift bytes, write and read.
        cmd_o <= framed_flit(
          std_ulogic_vector(to_unsigned(16#60# + dr_chunk_c - 1, 8)),
          last => false, valid => tok_in_ready = '1');
        tok_in_data(token_data_bit_c) <= '1';
        tok_in_data(4 downto 0) <=
          std_ulogic_vector(to_unsigned(dr_chunk_c - 1, 5));

      when CMD_BODY_DATA =>
        if r.preamble_left /= 0 then
          cmd_o <= framed_flit(preamble_byte_c, last => false);
        elsif r.sof_pending then
          cmd_o <= framed_flit(sof_byte_c, last => false);
        else
          cmd_o <= framed_flit(framer_byte_s, last => false);
        end if;
    end case;
  end process;

  -- One token per command opcode, pushed on acceptance.
  tok_in_valid <= cmd_i.ready when
                  r.cmd_state = CMD_DIV
                  or r.cmd_state = CMD_TLR or r.cmd_state = CMD_TLR_RTI
                  or r.cmd_state = CMD_IR_CAP or r.cmd_state = CMD_IR_OP
                  or r.cmd_state = CMD_DR_CAP or r.cmd_state = CMD_BODY_OP
                  or r.cmd_state = CMD_RUN
                  else '0';
  tok_out_ready <= '1' when r.rsp_state = RSP_TOKEN else '0';

  -- A framer byte is consumed for each accepted body byte past the
  -- preamble and SOF.
  framer_byte_ready_s <= cmd_i.ready when
                         r.cmd_state = CMD_BODY_DATA
                         and r.preamble_left = 0 and not r.sof_pending
                         else '0';
  framer_batch_start_s <= (cmd_i.ready and tok_in_ready)
                          when r.cmd_state = CMD_DR_CAP else '0';

  rsp_o <= framed_accept(r.rsp_state = RSP_DATA_GET or r.rsp_state = RSP_STATUS);

  des_shift_s <= '1' when r.rsp_state = RSP_UNPACK else '0';
  des_tdi_s <= r.rsp_shreg(0);
  des_capture_s <= r.rsp_capture;

  token_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 8,
      word_count_c => 8,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_data_i => tok_in_data,
      in_valid_i => tok_in_valid,
      in_ready_o => tok_in_ready,

      out_data_o => tok_out_data,
      out_valid_o => tok_out_valid,
      out_ready_i => tok_out_ready
      );

  framer: nsl_bnoc.chunked_link.chunked_link_master_framer
    generic map(
      flight_margin_c => flight_margin_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      batch_start_i => framer_batch_start_s,
      byte_ready_i => framer_byte_ready_s,
      byte_o => framer_byte_s,
      credit_set_i => credit_set_s,
      credit_i => credit_s,
      grant_i => r.grant_value,
      grant_valid_i => r.grant_pending,
      grant_ready_o => grant_ready_s,
      grant_sent_o => grant_sent_s,
      tx_data_i => tx_i.data,
      tx_last_i => tx_i.last,
      tx_valid_i => tx_i.valid,
      tx_ready_o => tx_o.ready,
      pending_o => pending_s,
      sendable_o => sendable_s
      );

  deserializer: nsl_jtag.continuous_transport.continuous_transport_deserializer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      shift_i => des_shift_s,
      capture_i => des_capture_s,
      tdi_i => des_tdi_s,
      locked_o => open,
      byte_o => des_byte_s,
      byte_valid_o => des_byte_valid_s
      );

  deframer: nsl_bnoc.chunked_link.chunked_link_deframer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      byte_i => des_byte_s,
      byte_valid_i => des_byte_valid_s,
      rx_data_o => rx_data_s,
      rx_last_o => rx_last_s,
      rx_valid_o => rx_valid_s,
      credit_o => credit_s,
      credit_set_o => credit_set_s,
      level_o => level_s,
      level_set_o => level_set_s,
      pad_o => open,
      pad_set_o => open
      );

  rx_o.data <= rx_data_s;
  rx_o.last <= rx_last_s;
  rx_o.valid <= rx_valid_s;

end architecture;
