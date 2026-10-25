library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_memory;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.dma_request.all;
use nsl_amba.axi_m2m_dma_priv.all;
use nsl_data.bytestream.all;

-- Thread engine of axi_m2m_microcoded_dma.
--
-- Channel contexts live in a context memory, eight 32-bit words a
-- channel: PC, SAR, DAR, CCR, loop counters, MFIFO pointers and the
-- scheduling word (state, what it waits for, request flags, fault
-- bits).  The memory has one read port and one write port, both driven
-- by this engine only, and a read latency of one cycle.  Registers
-- hold one working context, the one of the channel executing an
-- instruction, and a few flags per channel or event.
--
-- Idle, the engine scans one channel a cycle, round-robin: it reads
-- the channel's scheduling word and evaluates its wait against the
-- flags (event waits, peripheral request heads, transfers busy,
-- transfer errors).  A channel that can proceed is switched in: its
-- context words are read into the working context while its
-- instruction is fetched, the instruction executes, and the working
-- context words it changed are written back: one read-modify-write per
-- instruction.  A thread's PC is what CPC and DPC report: past a
-- waiting instruction (DMAWFE, DMAWFP, barriers, a discontinuous
-- DMAMOV) as soon as it executes, past DMAEND and DMAKILL, on an
-- instruction that faulted precisely, as the Zynq-7000's DMA-330.  A
-- wait resolving only switches the channel in again (emptying its
-- MFIFO after a discontinuity).
--
-- Scanning is pipelined: a channel's scheduling word is read, then
-- evaluated, then acted upon (written back, or the channel switched
-- in), while the next channels are read and evaluated.  A channel is
-- not read again while it is in this pipeline, so scanned data is
-- always current; nothing else writes a scheduling word while scans
-- are in flight.
--
-- An event waited for is a flag per channel and event: DMAWFE sets
-- the channel's, DMASEV clears the event's flags of every channel, and
-- a channel waiting for an event resumes once its flags are clear.
-- Instructions execute one at a time: a DMASEV and a DMAWFE never
-- happen together, the later one sees the effect of the earlier.
--
-- The manager thread runs on the same engine: it is switched in, has
-- its instruction fetched, decoded and executed, then its context
-- written back, as a channel's.  Its context is only a PC, the
-- scheduling fields and an event wait flag per event, so it lives in
-- registers rather than in the context memory: a ninth context, for
-- two meaningful words, would double the context memory at two and
-- four channels (it is sized to a power of two), and make the scan
-- tell the manager's slot from the channels'.  It is switched in
-- instead of the next channel scan when it can run and it is its
-- turn: after a channel instruction, or once the scan went round
-- every channel, as the DMA-330 serves the manager between two
-- channels.  Its DMAGO starts a channel as a debug DMAGO does.  Only
-- boot_from_pc_c starts the manager (debug instructions cannot), so
-- without it the manager never executes and its execution logic is
-- constant.
--
-- Debug instructions (DMAGO, DMASEV, DMAKILL through the debug
-- registers) are served between scans, once the scan reads in flight
-- were evaluated.  A debug instruction holds debug_ready_o low until it
-- executed.
--
-- Channel register reads never wait on the engine, which may itself
-- wait on an access to these registers (a channel loading its own
-- registers, or storing to them through an interconnect a host read
-- holds): a copy of the context memory, written along with it, has its
-- own read port for them.  They take three cycles and return the
-- registers as the last write-back left them: at most one instruction
-- stale, and two registers read one after the other may straddle an
-- instruction's write-back.
--
-- An instruction that can not proceed yet for lack of MFIFO room is
-- abandoned without side effect and fetched again next time the
-- channel is switched in.
--
-- Load and store transfer sizes and MFIFO accounting are computed over
-- several states, one addition per state.
entity axi_m2m_dma_thread is
  generic(
    config_c : nsl_amba.axi4_mm.config_t;
    channel_count_c : positive;
    event_count_c : positive;
    peripheral_count_c : positive;
    mfifo_depth_l2_c : positive;
    endian_swap_c : boolean;
    failed_store_fault_c : boolean;
    boot_from_pc_c : boolean;
    boot_addr_c : unsigned(31 downto 0)
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    debug_i : in debug_request_t;
    debug_ready_o : out std_ulogic;
    status_i : in status_request_t;
    status_ready_o : out std_ulogic;
    status_o : out status_response_t;
    manager_o : out manager_status_t;
    faulting_o : out std_ulogic_vector(0 to channel_count_c-1);
    events_o : out std_ulogic_vector(event_count_c-1 downto 0);

    irq_enable_i : in std_ulogic_vector(event_count_c-1 downto 0);
    irq_clear_i : in std_ulogic_vector(event_count_c-1 downto 0);
    irq_o : out std_ulogic_vector(event_count_c-1 downto 0);
    irq_abort_o : out std_ulogic;

    fetch_o : out fetch_request_t;
    fetch_ready_i : in std_ulogic;
    fetch_i : in fetch_response_t;

    load_o : out transfer_t;
    load_ready_i : in std_ulogic;
    store_o : out transfer_t;
    store_ready_i : in std_ulogic;

    read_busy_i : in std_ulogic_vector(0 to channel_count_c-1);
    write_busy_i : in std_ulogic_vector(0 to channel_count_c-1);
    read_error_i : in std_ulogic_vector(0 to channel_count_c-1);
    write_error_i : in std_ulogic_vector(0 to channel_count_c-1);
    released_i : in ptr_vector(0 to channel_count_c-1);
    pushed_i : in ptr_vector(0 to channel_count_c-1);
    poisoned_i : in std_ulogic_vector(0 to channel_count_c-1);
    poison_i : in ptr_vector(0 to channel_count_c-1);
    abort_o : out std_ulogic_vector(0 to channel_count_c-1);
    clear_o : out std_ulogic_vector(0 to channel_count_c-1);

    request_i : in request_state_vector(0 to peripheral_count_c-1);
    pop_o : out std_ulogic_vector(0 to peripheral_count_c-1);
    flush_o : out ack_request_t;
    flush_grant_i : in std_ulogic
    );
end entity;

architecture beh of axi_m2m_dma_thread is

  constant bus_l2_c : natural := config_c.data_bus_width_l2;
  constant bus_bytes_c : natural := 2**bus_l2_c;
  -- log2 of a channel's MFIFO size in bytes
  constant cap_l2_c : natural := mfifo_depth_l2_c + bus_l2_c;
  constant channel_l2_c : natural := nsl_math.arith.log2(channel_count_c);
  constant ctx_addr_size_c : natural := channel_l2_c + 3;

  subtype word_t is std_ulogic_vector(31 downto 0);
  subtype word_index_t is natural range 0 to 7;

  -- Context words of a channel
  constant word_pc_c : word_index_t := 0;
  constant word_sar_c : word_index_t := 1;
  constant word_dar_c : word_index_t := 2;
  constant word_ccr_c : word_index_t := 3;
  -- LC0 [7:0], LC1 [15:8]
  constant word_loop_c : word_index_t := 4;
  -- ld_ptr [15:0], st_ptr [31:16]
  constant word_ptr_c : word_index_t := 5;
  -- Scheduling word, see to_word(), last one written back
  constant word_sched_c : word_index_t := 6;
  -- Words a switched-in channel reads, from word_pc_c on
  constant load_words_c : natural := 6;

  type thread_state_t is (
    TS_STOPPED,
    TS_EXECUTING,
    TS_WFE,
    TS_WFP,
    TS_BARRIER,
    TS_KILLING,
    TS_COMPLETING,
    TS_FAULT_COMPLETING,
    TS_FAULTING
    );

  -- BARRIER_DISCARD is a DMAMOV's destination discontinuity: once
  -- the channel's transfers completed, its MFIFO is emptied.
  -- BARRIER_DATA is a DMAST whose data is not loaded yet, with
  -- failed_store_fault_c: once the channel's loads completed, it
  -- executes again, knowing whether a failed load brought its bytes.
  type barrier_t is (
    BARRIER_READ,
    BARRIER_WRITE,
    BARRIER_DISCARD,
    BARRIER_DATA
    );

  -- What a resolved wait does when the channel is switched in:
  -- nothing, or empty the MFIFO.
  type resume_t is (
    RESUME_NONE,
    RESUME_DISCARD
    );

  -- Fault bits kept in the scheduling word
  constant f_undef_c : natural := 0;
  constant f_operand_c : natural := 1;
  constant f_mfifo_c : natural := 2;
  constant f_st_data_c : natural := 3;
  constant f_fetch_c : natural := 4;
  subtype fault_bits_t is std_ulogic_vector(4 downto 0);

  type sched_t is
  record
    state: thread_state_t;
    barrier: barrier_t;
    resume: resume_t;
    -- Event or peripheral number waited for, reported while waited is
    -- set: from the DMAWFE or DMAWFP that waited until the wait
    -- resolves; a kill or a later DMAGO leaves it
    wakeup: unsigned(4 downto 0);
    waited: std_ulogic;
    wfp_burst: std_ulogic;
    wfp_periph: std_ulogic;
    -- request_type (burst when set) and request_last flags
    req_burst: std_ulogic;
    req_last: std_ulogic;
    -- Precise faults
    fault: fault_bits_t;
  end record;

  constant sched_reset_c : sched_t := (
    state => TS_STOPPED,
    barrier => BARRIER_READ,
    resume => RESUME_NONE,
    wakeup => (others => '0'),
    waited => '0',
    wfp_burst => '0',
    wfp_periph => '0',
    req_burst => '0',
    req_last => '0',
    fault => (others => '0')
    );

  -- Working context of the switched-in channel
  type context_t is
  record
    s: sched_t;
    pc: unsigned(31 downto 0);
    sar: unsigned(31 downto 0);
    dar: unsigned(31 downto 0);
    ccr: std_ulogic_vector(31 downto 0);
    lc0: unsigned(7 downto 0);
    lc1: unsigned(7 downto 0);
    ld_ptr: ptr_t;
    st_ptr: ptr_t;
  end record;

  type op_t is (
    OP_UNDEF,
    -- Invalid operand
    OP_INVALID,
    OP_END,
    OP_KILL,
    OP_NOP,
    OP_RMB,
    OP_WMB,
    OP_LD,
    OP_ST,
    OP_STZ,
    OP_LDP,
    OP_STP,
    OP_LP,
    OP_LPEND,
    OP_LPEND_FOREVER,
    OP_WFP,
    OP_SEV,
    OP_WFE,
    OP_FLUSHP,
    OP_ADDH,
    OP_ADNH,
    OP_MOV,
    OP_GO
    );

  type state_t is (
    ST_RESET,
    ST_INIT,
    ST_SCAN,
    ST_GAP,
    ST_DBG,
    ST_DBG_DECODE,
    ST_DBG_EXEC,
    ST_CMD_READ,
    ST_CMD_WAIT,
    ST_CMD_WRITE,
    ST_LOAD,
    ST_SWITCH,
    ST_FETCH,
    ST_FETCH_WAIT,
    ST_FETCH_CHECK,
    ST_DECODE,
    ST_XFER_SIZE,
    ST_XFER_BYTES,
    ST_XFER_CHECK,
    ST_XFER_SPACE,
    ST_XFER_ROOM,
    ST_XFER_WAIT,
    ST_FLUSH,
    ST_RETIRE,
    ST_WRITE_BACK
    );

  subtype channel_index_t is natural range 0 to channel_count_c-1;

  -- What a context memory read is for
  type read_kind_t is (
    READ_NONE,
    READ_SCAN,
    READ_LOAD,
    READ_CMD
    );

  type read_tag_t is
  record
    kind: read_kind_t;
    thread: channel_index_t;
    word: word_index_t;
  end record;

  constant read_none_c : read_tag_t := (
    kind => READ_NONE,
    thread => 0,
    word => 0
    );

  -- What evaluating a scanned channel does
  type scan_action_t is (
    SCAN_NONE,
    -- Writes its new scheduling word
    SCAN_WRITE,
    -- Switches it in with its new scheduling word
    SCAN_SWITCH,
    -- Pops a request it drops and leaves it waiting
    SCAN_DROP
    );

  type scan_result_t is
  record
    action: scan_action_t;
    s: sched_t;
    -- Pops the head of the request FIFO of peripheral s.wakeup
    pop: boolean;
    -- Faults: its event waits go, it is faulting
    faults: boolean;
    -- Stops after a kill
    stops: boolean;
  end record;

  -- What a channel command (a DMAGO, a debug DMAKILL) does to its
  -- channel: start it at pc, or kill it.
  type cmd_kind_t is (
    CMD_START,
    CMD_KILL
    );

  type cmd_t is
  record
    kind: cmd_kind_t;
    channel: channel_t;
    pc: unsigned(31 downto 0);
  end record;

  type event_wait_vector is array (natural range <>) of std_ulogic_vector(event_count_c-1 downto 0);
  subtype word_mask_t is std_ulogic_vector(0 to 7);

  type regs_t is
  record
    state: state_t;
    -- Debug instruction, valid until executed
    dbg: debug_request_t;
    cmd: cmd_t;
    -- Channel register read: request, request whose status memory word
    -- comes this cycle, response
    sreq: status_request_t;
    sdata: status_request_t;
    sresp: status_response_t;
    -- Next channel to scan
    scan: channel_index_t;
    -- Evaluation of the scheduling word read last cycle, acted upon
    -- this cycle
    ev: scan_result_t;
    ev_valid: boolean;
    ev_thread: channel_index_t;
    -- Switched-in thread, valid when live: the manager if mgr_live,
    -- channel cur otherwise
    cur: channel_index_t;
    live: boolean;
    mgr_live: boolean;
    -- Manager context
    mgr: sched_t;
    mgr_pc: unsigned(31 downto 0);
    mgr_waits: std_ulogic_vector(event_count_c-1 downto 0);
    -- The manager goes before the next channel
    mgr_turn: boolean;
    w: context_t;
    -- Context words read so far, next word to read
    loaded: word_mask_t;
    load_next: natural range 0 to load_words_c;
    -- Context words to write back
    dirty: word_mask_t;
    -- Words a start command writes
    cmd_writes: word_mask_t;
    init: natural range 0 to 8 * channel_count_c;

    -- Context memory read issued this cycle, read whose data comes
    -- this cycle, write done this cycle
    rtag: read_tag_t;
    dtag: read_tag_t;
    wen: std_ulogic;
    wthread: channel_index_t;
    wword: word_index_t;
    wdata: word_t;

    -- Instruction bytes fetched so far
    ibuf: byte_string(0 to 5);
    -- Instruction buffer position of the first byte of the next
    -- fetched bus word, negative for the bytes of the first word
    -- before the PC.  Once a word is appended, count of bytes in the
    -- buffer.
    ipos: signed(5 downto 0);
    fetch: fetch_request_t;
    -- Address of the next instruction
    npc: unsigned(31 downto 0);
    -- Decoded instruction, which the switched-in thread may execute
    -- when allowed
    op: op_t;
    allowed: boolean;
    cond_ok: boolean;
    periph_bad: boolean;
    event_bad: boolean;
    -- Some channel waits for the event operand
    event_waited: boolean;

    -- Transfer being prepared
    x_store: std_ulogic;
    x_zero: std_ulogic;
    x_size_l2: unsigned(2 downto 0);
    x_len_m1: unsigned(3 downto 0);
    x_incr: std_ulogic;
    x_addr: unsigned(31 downto 0);
    x_lenbytes: unsigned(8 downto 0);
    x_head: unsigned(4 downto 0);
    x_bytes: unsigned(8 downto 0);
    x_end: ptr_t;
    x_released: ptr_t;
    x_room: ptr_t;
    x_avail: ptr_t;
    x_drained: boolean;
    -- A store: bytes loaded beyond its end, from the first failed
    -- load's bytes to its end
    x_pushed: ptr_t;
    x_poison: ptr_t;
    x_poisoned: boolean;
    x_addr_next: unsigned(31 downto 0);
    xfer: transfer_t;

    pop: std_ulogic_vector(0 to peripheral_count_c-1);
    flush: ack_request_t;
    clear: std_ulogic_vector(0 to channel_count_c-1);

    -- Per event: INT_EVENT_RIS, an interrupt raised where INTEN is set,
    -- a pending event where it is clear, as on the Zynq's DMA-330
    active: std_ulogic_vector(event_count_c-1 downto 0);
    -- Per channel and event: waits for the event, not woken yet
    waits: event_wait_vector(0 to channel_count_c-1);
    -- Per channel
    killing: std_ulogic_vector(0 to channel_count_c-1);
    faulting: std_ulogic_vector(0 to channel_count_c-1);
    -- Imprecise faults
    rd_err: std_ulogic_vector(0 to channel_count_c-1);
    wr_err: std_ulogic_vector(0 to channel_count_c-1);
    -- Transfers in flight, a cycle late.  Only the switched-in channel
    -- hands transfers over: a channel scanned was not busy a cycle ago
    -- is not busy now.
    rd_busy: std_ulogic_vector(0 to channel_count_c-1);
    wr_busy: std_ulogic_vector(0 to channel_count_c-1);
  end record;

  signal r, rin: regs_t;

  signal ctx_raddr_s, ctx_waddr_s : unsigned(ctx_addr_size_c-1 downto 0);
  signal ctx_wen_s : std_ulogic_vector(0 downto 0);
  signal ctx_wdata_s, ctx_rdata_s : word_t;
  signal status_raddr_s : unsigned(ctx_addr_size_c-1 downto 0);
  signal status_rdata_s : word_t;

  function ctx_addr(thread : channel_index_t; word : word_index_t) return unsigned is
  begin
    return to_unsigned(thread, channel_l2_c) & to_unsigned(word, 3);
  end function;

  function next_channel(c : channel_index_t) return channel_index_t is
  begin
    if c = channel_count_c-1 then
      return 0;
    else
      return c + 1;
    end if;
  end function;

  function state_code(s : thread_state_t) return channel_state_t is
  begin
    case s is
      when TS_STOPPED => return channel_stopped_c;
      when TS_EXECUTING => return channel_executing_c;
      when TS_WFE => return channel_waiting_event_c;
      when TS_WFP => return channel_waiting_peripheral_c;
      when TS_BARRIER => return channel_at_barrier_c;
      when TS_KILLING => return channel_killing_c;
      when TS_COMPLETING => return channel_completing_c;
      when TS_FAULT_COMPLETING => return channel_faulting_completing_c;
      when TS_FAULTING => return channel_faulting_c;
    end case;
  end function;

  function code_state(c : std_ulogic_vector(3 downto 0)) return thread_state_t is
  begin
    case c is
      when channel_executing_c => return TS_EXECUTING;
      when channel_waiting_event_c => return TS_WFE;
      when channel_waiting_peripheral_c => return TS_WFP;
      when channel_at_barrier_c => return TS_BARRIER;
      when channel_killing_c => return TS_KILLING;
      when channel_completing_c => return TS_COMPLETING;
      when channel_faulting_completing_c => return TS_FAULT_COMPLETING;
      when channel_faulting_c => return TS_FAULTING;
      when others => return TS_STOPPED;
    end case;
  end function;

  -- Scheduling word: state [3:0] (CSR encoding), barrier [5:4],
  -- resume [6], waited [7], wakeup [12:8], wfp_burst [13],
  -- wfp_periph [14], req_burst [15], req_last [16], fault [21:17].
  function to_word(s : sched_t) return word_t is
    variable ret : word_t := (others => '0');
  begin
    ret(3 downto 0) := state_code(s.state);
    ret(5 downto 4) := std_ulogic_vector(to_unsigned(barrier_t'pos(s.barrier), 2));
    if s.resume = RESUME_DISCARD then
      ret(6) := '1';
    end if;
    ret(7) := s.waited;
    ret(12 downto 8) := std_ulogic_vector(s.wakeup);
    ret(13) := s.wfp_burst;
    ret(14) := s.wfp_periph;
    ret(15) := s.req_burst;
    ret(16) := s.req_last;
    ret(21 downto 17) := s.fault;
    return ret;
  end function;

  function to_sched(w : word_t) return sched_t is
    variable ret : sched_t;
  begin
    ret.state := code_state(w(3 downto 0));
    case w(5 downto 4) is
      when "01" => ret.barrier := BARRIER_WRITE;
      when "10" => ret.barrier := BARRIER_DISCARD;
      when "11" => ret.barrier := BARRIER_DATA;
      when others => ret.barrier := BARRIER_READ;
    end case;
    if w(6) = '1' then
      ret.resume := RESUME_DISCARD;
    else
      ret.resume := RESUME_NONE;
    end if;
    ret.waited := w(7);
    ret.wakeup := unsigned(w(12 downto 8));
    ret.wfp_burst := w(13);
    ret.wfp_periph := w(14);
    ret.req_burst := w(15);
    ret.req_last := w(16);
    ret.fault := w(21 downto 17);
    return ret;
  end function;

  -- Scheduling word of a channel command's channel
  function command_word(s : sched_t; cmd : cmd_t) return word_t is
    variable ret : sched_t := s;
  begin
    ret.resume := RESUME_NONE;
    case cmd.kind is
      when CMD_KILL =>
        ret.fault := (others => '0');
        ret.state := TS_KILLING;
      when CMD_START =>
        ret.fault := (others => '0');
        ret.state := TS_EXECUTING;
        ret.req_burst := '0';
        ret.req_last := '0';
    end case;
    return to_word(ret);
  end function;

  -- Fault bits of a thread in the FTR / FTRD layout
  function fault_register(f : fault_bits_t) return std_ulogic_vector is
    variable ret : std_ulogic_vector(31 downto 0) := (others => '0');
  begin
    ret(fault_undef_instr_c) := f(f_undef_c);
    ret(fault_operand_invalid_c) := f(f_operand_c);
    ret(fault_mfifo_err_c) := f(f_mfifo_c);
    ret(fault_st_data_unavailable_c) := f(f_st_data_c);
    ret(fault_instr_fetch_err_c) := f(f_fetch_c);
    return ret;
  end function;

  -- Context word initial value
  function word_reset(word : word_index_t) return word_t is
  begin
    case word is
      -- DMA-330 CCR reset value
      when word_ccr_c => return x"00800200";
      when word_sched_c => return to_word(sched_reset_c);
      when others => return (others => '0');
    end case;
  end function;

  -- Context word of the working context
  function context_word(w : context_t; word : word_index_t) return word_t is
  begin
    case word is
      when word_pc_c => return std_ulogic_vector(w.pc);
      when word_sar_c => return std_ulogic_vector(w.sar);
      when word_dar_c => return std_ulogic_vector(w.dar);
      when word_ccr_c => return w.ccr;
      when word_loop_c => return x"0000" & std_ulogic_vector(w.lc1) & std_ulogic_vector(w.lc0);
      when word_ptr_c => return std_ulogic_vector(w.st_ptr) & std_ulogic_vector(w.ld_ptr);
      when others => return to_word(w.s);
    end case;
  end function;

  -- Lowest word set in a mask
  function first_word(m : word_mask_t) return word_index_t is
  begin
    for i in m'range
    loop
      if m(i) = '1' then
        return i;
      end if;
    end loop;
    return 0;
  end function;

  function without(m : word_mask_t; word : word_index_t) return word_mask_t is
    variable ret : word_mask_t := m;
  begin
    ret(word) := '0';
    return ret;
  end function;

  function mask_of(word : word_index_t) return word_mask_t is
    variable ret : word_mask_t := (others => '0');
  begin
    ret(word) := '1';
    return ret;
  end function;

  -- Context word holding a channel register
  function status_word(reg : channel_register_t) return word_index_t is
  begin
    case reg is
      when CHANNEL_CPC => return word_pc_c;
      when CHANNEL_SAR => return word_sar_c;
      when CHANNEL_DAR => return word_dar_c;
      when CHANNEL_CCR => return word_ccr_c;
      when CHANNEL_LC0 | CHANNEL_LC1 => return word_loop_c;
      when others => return word_sched_c;
    end case;
  end function;

  -- Channel register value from the context word holding it
  function status_value(reg : channel_register_t; data : word_t;
                        rd_err, wr_err : std_ulogic) return word_t is
    variable s : sched_t;
    variable ret : word_t := (others => '0');
  begin
    s := to_sched(data);
    case reg is
      when CHANNEL_CSR =>
        ret(3 downto 0) := state_code(s.state);
        if s.waited = '1' then
          ret(8 downto 4) := std_ulogic_vector(s.wakeup);
        end if;
        ret(14) := s.wfp_burst;
        ret(15) := s.wfp_periph;
      when CHANNEL_LC0 =>
        ret(7 downto 0) := data(7 downto 0);
      when CHANNEL_LC1 =>
        ret(7 downto 0) := data(15 downto 8);
      when CHANNEL_FTR =>
        ret := fault_register(s.fault);
        -- Transfer errors show once they faulted the channel
        if s.state = TS_FAULTING or s.state = TS_FAULT_COMPLETING then
          ret(fault_data_read_err_c) := rd_err;
          ret(fault_data_write_err_c) := wr_err;
        end if;
      when others =>
        ret := data;
    end case;
    return ret;
  end function;

  function decode(op : byte) return op_t is
  begin
    case op is
      when x"00" => return OP_END;
      when x"01" => return OP_KILL;
      when x"04" | x"05" | x"07" => return OP_LD;
      when x"08" | x"09" | x"0b" => return OP_ST;
      when x"0c" => return OP_STZ;
      when x"12" => return OP_RMB;
      when x"13" => return OP_WMB;
      when x"18" => return OP_NOP;
      when x"20" | x"22" => return OP_LP;
      when x"25" | x"27" => return OP_LDP;
      when x"29" | x"2b" => return OP_STP;
      when x"2c" => return OP_LPEND_FOREVER;
      when x"30" | x"31" | x"32" => return OP_WFP;
      when x"34" => return OP_SEV;
      when x"35" => return OP_FLUSHP;
      when x"36" => return OP_WFE;
      when x"38" | x"39" | x"3b" | x"3c" | x"3d" | x"3f" => return OP_LPEND;
      when x"54" | x"56" => return OP_ADDH;
      when x"5c" | x"5e" => return OP_ADNH;
      when x"bc" => return OP_MOV;
      when x"a0" | x"a2" => return OP_GO;
      when others => return OP_UNDEF;
    end case;
  end function;

  -- Instruction with its operand byte, OP_INVALID for a DMAMOV to a
  -- register other than SAR, CCR and DAR and a DMAGO with reserved
  -- bits set.  Other reserved operand bits are ignored, as the
  -- Zynq-7000's DMA-330 does.
  function decode_operand(op, b1 : byte) return op_t is
  begin
    case decode(op) is
      when OP_MOV =>
        if unsigned(b1(2 downto 0)) > 2 then
          return OP_INVALID;
        end if;
      when OP_GO =>
        if b1(7 downto 3) /= "00000" then
          return OP_INVALID;
        end if;
      when others =>
        null;
    end case;
    return decode(op);
  end function;

  -- The manager (manager true) or a channel may execute op
  function thread_allows(op : op_t; manager : boolean) return boolean is
  begin
    case op is
      when OP_END | OP_KILL | OP_NOP | OP_SEV | OP_WFE | OP_UNDEF | OP_INVALID =>
        return true;
      when OP_GO =>
        return manager;
      when others =>
        return not manager;
    end case;
  end function;

  function instruction_length(op : byte) return unsigned is
  begin
    case decode(op) is
      when OP_LP | OP_LDP | OP_STP | OP_LPEND | OP_LPEND_FOREVER
        | OP_WFP | OP_SEV | OP_FLUSHP | OP_WFE =>
        return to_unsigned(2, 3);
      when OP_ADDH | OP_ADNH =>
        return to_unsigned(3, 3);
      when OP_MOV | OP_GO =>
        return to_unsigned(6, 3);
      when others =>
        return to_unsigned(1, 3);
    end case;
  end function;

  -- Appends a fetched bus word to the instruction buffer, byte k at
  -- position pos + k.
  function ibuf_append(ibuf : byte_string(0 to 5);
                       pos : signed(5 downto 0);
                       word : byte_string) return byte_string
  is
    variable ret : byte_string(0 to 5) := ibuf;
  begin
    for j in ret'range
    loop
      for k in 0 to word'length-1
      loop
        if pos = to_signed(j - k, pos'length) then
          ret(j) := word(word'left + k);
        end if;
      end loop;
    end loop;
    return ret;
  end function;

  -- Immediates of DMAADDH/DMAADNH and DMAMOV, little endian
  function imm16(ibuf : byte_string(0 to 5)) return unsigned is
    variable ret : unsigned(15 downto 0);
  begin
    ret(7 downto 0) := unsigned(ibuf(1));
    ret(15 downto 8) := unsigned(ibuf(2));
    return ret;
  end function;

  function imm32(ibuf : byte_string(0 to 5)) return unsigned is
    variable ret : unsigned(31 downto 0);
  begin
    for i in 0 to 3
    loop
      ret(8*i+7 downto 8*i) := unsigned(ibuf(i+2));
    end loop;
    return ret;
  end function;

  function is_set(v : std_ulogic_vector; index : unsigned) return boolean
  is
  begin
    for i in v'range
    loop
      if index = to_unsigned(i, index'length) then
        return v(i) = '1';
      end if;
    end loop;
    return false;
  end function;

  -- Head of the request FIFO of a peripheral
  function request_of(requests : request_state_vector; periph : unsigned(4 downto 0))
    return request_state_t
  is
  begin
    for p in requests'range
    loop
      if periph = to_unsigned(p, 5) then
        return requests(p);
      end if;
    end loop;
    return requests(requests'left);
  end function;

  -- Some channel waits for the event
  function waited(waits : event_wait_vector; event : unsigned(4 downto 0)) return boolean
  is
  begin
    for c in waits'range
    loop
      if is_set(waits(c), event) then
        return true;
      end if;
    end loop;
    return false;
  end function;

  -- A DMAMOV CCR of value ccr after old is a destination discontinuity
  function ccr_discontinuity(old, ccr : std_ulogic_vector(31 downto 0)) return boolean is
  begin
    return ccr(30 downto 28) /= old(30 downto 28)
      or ccr(14) /= old(14)
      or (ccr(14) = '0' and ccr(17 downto 15) /= old(17 downto 15));
  end function;

  -- Transfer size in bytes exceeds the channel MFIFO
  function too_big(bytes : unsigned(8 downto 0)) return boolean is
  begin
    return resize(bytes, 16) > to_unsigned(2**cap_l2_c, 16);
  end function;

  -- Pointer difference fits in channel MFIFO
  function fits(diff : ptr_t) return boolean is
  begin
    return diff <= to_unsigned(2**cap_l2_c, ptr_t'length);
  end function;

  -- Evaluation of a scanned channel's scheduling word s.  err is an
  -- imprecise fault, rd_busy and wr_busy tell its transfers in flight,
  -- waits that it waits for an event not sent yet, req is the head of
  -- the request FIFO of the peripheral it waits for.
  function scan_eval(s : sched_t;
                     rd_err, wr_err, rd_busy, wr_busy, waits : boolean;
                     req : request_state_t) return scan_result_t
  is
    variable ret : scan_result_t;
  begin
    ret.action := SCAN_NONE;
    ret.s := s;
    ret.pop := false;
    ret.faults := false;
    ret.stops := false;

    case s.state is
      when TS_STOPPED | TS_FAULTING =>
        null;

      when TS_KILLING =>
        if not rd_busy and not wr_busy then
          ret.action := SCAN_WRITE;
          ret.s.state := TS_STOPPED;
          ret.stops := true;
        end if;

      when TS_FAULT_COMPLETING =>
        if not rd_busy and not wr_busy then
          ret.action := SCAN_WRITE;
          ret.s.state := TS_FAULTING;
        end if;

      when others =>
        -- A transfer error faults the channel once it waits for its
        -- transfers to complete (DMAEND, a barrier, a discontinuity),
        -- as the Zynq's DMA-330 does: until then, it executes on.
        case s.state is
          when TS_EXECUTING =>
            ret.action := SCAN_SWITCH;

          when TS_COMPLETING =>
            if not rd_busy and not wr_busy then
              ret.action := SCAN_WRITE;
              if rd_err or wr_err then
                ret.s.state := TS_FAULTING;
                ret.faults := true;
              else
                ret.s.state := TS_STOPPED;
              end if;
            end if;

          when TS_WFE =>
            if not waits then
              ret.action := SCAN_SWITCH;
              ret.s.state := TS_EXECUTING;
              ret.s.waited := '0';
            end if;

          when TS_WFP =>
            if req.valid = '1' then
              if s.wfp_periph = '1' then
                ret.action := SCAN_SWITCH;
                ret.s.req_burst := req.burst;
                ret.s.req_last := req.last;
                ret.pop := true;
              elsif s.wfp_burst = '0' then
                -- DMAWFP single takes a single request, leaves a
                -- burst one.
                ret.action := SCAN_SWITCH;
                ret.s.req_burst := '0';
                ret.s.req_last := '0';
                ret.pop := req.burst = '0';
              elsif req.burst = '1' then
                ret.action := SCAN_SWITCH;
                ret.s.req_burst := '1';
                ret.s.req_last := '0';
                ret.pop := true;
              else
                -- DMAWFP burst drops a single request
                ret.action := SCAN_DROP;
                ret.pop := true;
              end if;
              if ret.action = SCAN_SWITCH then
                ret.s.state := TS_EXECUTING;
                ret.s.waited := '0';
              end if;
            end if;

          when TS_BARRIER =>
            case s.barrier is
              when BARRIER_READ =>
                if not rd_busy then
                  ret.action := SCAN_SWITCH;
                  ret.faults := rd_err;
                end if;
              when BARRIER_WRITE =>
                if not wr_busy then
                  ret.action := SCAN_SWITCH;
                  ret.faults := wr_err;
                end if;
              when BARRIER_DISCARD =>
                if not rd_busy and not wr_busy then
                  ret.action := SCAN_SWITCH;
                  ret.s.resume := RESUME_DISCARD;
                  ret.faults := rd_err or wr_err;
                end if;
              when BARRIER_DATA =>
                if not rd_busy then
                  ret.action := SCAN_SWITCH;
                end if;
            end case;
            if ret.faults then
              ret.action := SCAN_WRITE;
              ret.s.state := TS_FAULTING;
              ret.s.resume := RESUME_NONE;
            elsif ret.action = SCAN_SWITCH then
              ret.s.state := TS_EXECUTING;
            end if;

          when others =>
            null;
        end case;
    end case;
    return ret;
  end function;

begin

  assert cap_l2_c <= max_mfifo_channel_bytes_l2_c
    report "Channel MFIFO larger than 4 kB is not supported"
    severity failure;

  context_ram: nsl_memory.ram.ram_auto
    generic map(
      addr_size_c => ctx_addr_size_c,
      word_size_c => 32,
      data_word_count_c => 1
      )
    port map(
      clock_i => clock_i,

      write_address_i => ctx_waddr_s,
      write_en_i => ctx_wen_s,
      write_data_i => ctx_wdata_s,

      read_address_i => ctx_raddr_s,
      read_data_o => ctx_rdata_s
      );

  -- A copy of the context memory, written along with it, read by
  -- channel register reads only: they never wait on the engine.
  status_ram: nsl_memory.ram.ram_auto
    generic map(
      addr_size_c => ctx_addr_size_c,
      word_size_c => 32,
      data_word_count_c => 1
      )
    port map(
      clock_i => clock_i,

      write_address_i => ctx_waddr_s,
      write_en_i => ctx_wen_s,
      write_data_i => ctx_wdata_s,

      read_address_i => status_raddr_s,
      read_data_o => status_rdata_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.dbg.valid <= '0';
      r.sreq.valid <= '0';
      r.sdata.valid <= '0';
      r.sresp.valid <= '0';
      r.live <= false;
      r.mgr_live <= false;
      r.mgr.state <= TS_STOPPED;
      r.rtag.kind <= READ_NONE;
      r.dtag.kind <= READ_NONE;
      r.ev_valid <= false;
      r.wen <= '0';
      r.fetch.valid <= '0';
      r.xfer.valid <= '0';
      r.flush.valid <= '0';
      r.pop <= (others => '0');
      r.clear <= (others => '0');
      r.active <= (others => '0');
      r.killing <= (others => '0');
      r.faulting <= (others => '0');
    end if;
  end process;

  transition: process(r, debug_i, status_i, irq_enable_i, irq_clear_i,
                      fetch_ready_i, fetch_i, load_ready_i, store_ready_i,
                      read_busy_i, write_busy_i, read_error_i, write_error_i,
                      released_i, pushed_i, poisoned_i, poison_i,
                      request_i, flush_grant_i, ctx_rdata_s, status_rdata_s) is
    variable op : byte;
    variable b1 : byte;
    variable lc : unsigned(7 downto 0);
    -- Channel whose context word comes this cycle
    variable x : channel_index_t;
    -- That word as a scheduling word, and its evaluation
    variable xs : sched_t;
    variable sr : scan_result_t;
    -- The scan evaluated last cycle switches a channel in or drops a
    -- request
    variable leaves : boolean;
    -- Word written back this cycle
    variable wb : word_index_t;
    -- The manager can run and it is its turn
    variable mgr_go : boolean;
    -- Event, peripheral or channel operand of the instruction
    variable operand : unsigned(4 downto 0);
    -- Pending events: raw status bits whose interrupt is disabled
    variable pending : std_ulogic_vector(event_count_c-1 downto 0);
  begin
    rin <= r;

    rin.pop <= (others => '0');
    rin.clear <= (others => '0');
    rin.sresp.valid <= '0';
    rin.wen <= '0';
    rin.rtag <= read_none_c;
    rin.dtag <= r.rtag;
    rin.rd_busy <= read_busy_i;
    rin.wr_busy <= write_busy_i;

    -- Errors of transfers a kill drops are not faults
    for c in 0 to channel_count_c-1
    loop
      if read_error_i(c) = '1' and r.killing(c) = '0' then
        rin.rd_err(c) <= '1';
      end if;
      if write_error_i(c) = '1' and r.killing(c) = '0' then
        rin.wr_err(c) <= '1';
      end if;
    end loop;

    for e in 0 to event_count_c-1
    loop
      if irq_clear_i(e) = '1' and irq_enable_i(e) = '1' then
        rin.active(e) <= '0';
      end if;
    end loop;

    op := r.ibuf(0);
    b1 := r.ibuf(1);
    if op(2) = '0' then
      lc := r.w.lc0;
    else
      lc := r.w.lc1;
    end if;
    x := r.dtag.thread;
    xs := to_sched(ctx_rdata_s);
    sr := scan_eval(xs,
                    r.rd_err(x) = '1' or read_error_i(x) = '1',
                    r.wr_err(x) = '1' or write_error_i(x) = '1',
                    r.rd_busy(x) = '1', r.wr_busy(x) = '1',
                    r.waits(x) /= (r.waits(x)'range => '0'),
                    request_of(request_i, xs.wakeup));
    leaves := r.ev_valid and (r.ev.action = SCAN_SWITCH or r.ev.action = SCAN_DROP);
    rin.ev <= sr;
    rin.ev_thread <= x;
    rin.ev_valid <= false;
    wb := first_word(r.dirty);
    -- Without boot_from_pc_c, nothing starts the manager: its execution
    -- logic goes away.
    mgr_go := boot_from_pc_c and r.mgr_turn
              and (r.mgr.state = TS_EXECUTING
                   or (r.mgr.state = TS_WFE and r.mgr_waits = (r.mgr_waits'range => '0')));
    operand := unsigned(b1(7 downto 3));
    pending := r.active and not irq_enable_i;

    if r.dbg.valid = '0' and debug_i.valid = '1' then
      rin.dbg <= debug_i;
    end if;

    -- Channel register reads, a pipeline independent of the engine:
    -- request, status memory read, response.
    rin.sreq <= status_i;
    rin.sdata <= r.sreq;
    if r.sdata.valid = '1' then
      rin.sresp.valid <= '1';
      rin.sresp.data <= (others => '0');
      for c in 0 to channel_count_c-1
      loop
        if r.sdata.channel = to_unsigned(c, channel_t'length) then
          rin.sresp.data <= status_value(r.sdata.reg, status_rdata_s, r.rd_err(c), r.wr_err(c));
        end if;
      end loop;
    end if;

    -- Context words of the switched-in channel
    if r.dtag.kind = READ_LOAD then
      rin.loaded(r.dtag.word) <= '1';
      case r.dtag.word is
        when word_pc_c =>
          rin.w.pc <= unsigned(ctx_rdata_s);
        when word_sar_c =>
          rin.w.sar <= unsigned(ctx_rdata_s);
        when word_dar_c =>
          rin.w.dar <= unsigned(ctx_rdata_s);
        when word_ccr_c =>
          rin.w.ccr <= ctx_rdata_s;
        when word_loop_c =>
          rin.w.lc0 <= unsigned(ctx_rdata_s(7 downto 0));
          rin.w.lc1 <= unsigned(ctx_rdata_s(15 downto 8));
        when others =>
          if r.w.s.resume = RESUME_DISCARD then
            rin.w.ld_ptr <= (others => '0');
            rin.w.st_ptr <= (others => '0');
            rin.dirty(word_ptr_c) <= '1';
            rin.clear(r.cur) <= '1';
          else
            rin.w.ld_ptr <= ptr_wrap(unsigned(ctx_rdata_s(15 downto 0)), cap_l2_c);
            rin.w.st_ptr <= ptr_wrap(unsigned(ctx_rdata_s(31 downto 16)), cap_l2_c);
          end if;
          rin.w.s.resume <= RESUME_NONE;
      end case;
    end if;

    if r.live and r.load_next /= load_words_c then
      rin.rtag <= (kind => READ_LOAD, thread => r.cur, word => r.load_next);
      rin.load_next <= r.load_next + 1;
    end if;

    case r.state is
      when ST_RESET =>
        rin.active <= (others => '0');
        rin.rd_err <= (others => '0');
        rin.wr_err <= (others => '0');
        rin.waits <= (others => (others => '0'));
        rin.scan <= 0;
        rin.init <= 0;
        rin.mgr <= sched_reset_c;
        if boot_from_pc_c then
          rin.mgr.state <= TS_EXECUTING;
        end if;
        rin.mgr_pc <= boot_addr_c;
        rin.mgr_waits <= (others => '0');
        rin.mgr_turn <= true;
        rin.state <= ST_INIT;

      when ST_INIT =>
        rin.wen <= '1';
        rin.wthread <= r.init / 8;
        rin.wword <= r.init mod 8;
        rin.wdata <= word_reset(r.init mod 8);
        if r.init = 8 * channel_count_c - 1 then
          rin.state <= ST_SCAN;
        else
          rin.init <= r.init + 1;
        end if;

      when ST_SCAN =>
        if r.ev_valid then
          case r.ev.action is
            when SCAN_NONE =>
              null;

            when SCAN_WRITE =>
              rin.wen <= '1';
              rin.wthread <= r.ev_thread;
              rin.wword <= word_sched_c;
              rin.wdata <= to_word(r.ev.s);
              if r.ev.faults then
                rin.faulting(r.ev_thread) <= '1';
                rin.waits(r.ev_thread) <= (others => '0');
              end if;
              if r.ev.stops then
                rin.killing(r.ev_thread) <= '0';
              end if;

            when SCAN_SWITCH =>
              rin.cur <= r.ev_thread;
              rin.live <= true;
              rin.w.s <= r.ev.s;
              rin.loaded <= (others => '0');
              rin.load_next <= 0;
              rin.dirty <= (others => '0');
              rin.state <= ST_LOAD;

            when SCAN_DROP =>
              rin.scan <= next_channel(r.ev_thread);
              rin.state <= ST_GAP;
          end case;

          if r.ev.pop then
            for p in 0 to peripheral_count_c-1
            loop
              if r.ev.s.wakeup = to_unsigned(p, 5) then
                rin.pop(p) <= '1';
              end if;
            end loop;
          end if;
        end if;

        if not leaves then
          rin.ev_valid <= r.dtag.kind = READ_SCAN;
          if r.dbg.valid = '1' or mgr_go then
            -- Served once the scan reads in flight are evaluated
            if r.rtag.kind /= READ_SCAN and r.dtag.kind /= READ_SCAN then
              if r.dbg.valid = '1' then
                rin.state <= ST_DBG;
              else
                -- Switches the manager in
                rin.live <= true;
                rin.mgr_live <= true;
                rin.w.s <= r.mgr;
                rin.w.s.state <= TS_EXECUTING;
                rin.w.s.waited <= '0';
                rin.w.pc <= r.mgr_pc;
                rin.loaded <= (others => '1');
                rin.load_next <= load_words_c;
                rin.dirty <= (others => '0');
                rin.state <= ST_SWITCH;
              end if;
            end if;
          elsif not (r.rtag.kind = READ_SCAN and r.rtag.thread = r.scan)
            and not (r.dtag.kind = READ_SCAN and r.dtag.thread = r.scan)
            and not (r.ev_valid and r.ev_thread = r.scan) then
            -- Next channel, unless it is being scanned already (few
            -- channels): its scheduling word may be written.
            rin.rtag <= (kind => READ_SCAN, thread => r.scan, word => word_sched_c);
            rin.scan <= next_channel(r.scan);
            if r.scan = channel_count_c-1 then
              rin.mgr_turn <= true;
            end if;
          end if;
        end if;

      when ST_GAP =>
        -- Lets the peripheral block take a pop before the next scan
        rin.state <= ST_SCAN;

      when ST_DBG =>
        rin.ibuf <= r.dbg.inst;
        rin.state <= ST_DBG_DECODE;

      when ST_DBG_DECODE =>
        rin.op <= decode_operand(op, b1);
        rin.allowed <= true;
        rin.event_bad <= operand >= event_count_c;
        rin.event_waited <= waited(r.waits, operand) or is_set(r.mgr_waits, operand);
        rin.state <= ST_DBG_EXEC;

      when ST_DBG_EXEC =>
        -- Done, unless a command or DMASEV follows.  As on the Zynq's
        -- DMA-330, instructions other than DMAGO (to the manager),
        -- DMASEV and DMAKILL are ignored, and so are invalid operands
        -- (a DMAGO with reserved bits, an event or channel beyond the
        -- configuration), whatever the thread's state.
        rin.state <= ST_RETIRE;
        rin.cmd.channel <= r.dbg.channel;
        rin.cmd.pc <= imm32(r.ibuf);
        if r.dbg.channel_thread = '0' then
          case r.op is
            when OP_GO =>
              if unsigned(b1(2 downto 0)) < channel_count_c then
                rin.cmd.kind <= CMD_START;
                rin.cmd.channel <= unsigned(b1(2 downto 0));
                rin.state <= ST_CMD_READ;
              end if;

            when OP_SEV =>
              if not r.event_bad then
                rin.state <= ST_DECODE;
              end if;

            when OP_KILL =>
              rin.mgr.state <= TS_STOPPED;
              rin.mgr.fault <= (others => '0');
              rin.mgr_waits <= (others => '0');

            when others =>
              null;
          end case;
        elsif to_integer(r.dbg.channel) < channel_count_c then
          case r.op is
            when OP_KILL =>
              rin.cmd.kind <= CMD_KILL;
              rin.state <= ST_CMD_READ;

            when OP_SEV =>
              if not r.event_bad then
                rin.state <= ST_DECODE;
              end if;

            when others =>
              null;
          end case;
        end if;

      when ST_CMD_READ =>
        rin.rtag <= (kind => READ_CMD, thread => to_integer(r.cmd.channel), word => word_sched_c);
        rin.state <= ST_CMD_WAIT;

      when ST_CMD_WAIT =>
        if r.dtag.kind = READ_CMD then
          rin.state <= ST_RETIRE;
          rin.wthread <= x;
          rin.wword <= word_sched_c;
          rin.wdata <= command_word(xs, r.cmd);
          case r.cmd.kind is
            when CMD_KILL =>
              if xs.state /= TS_STOPPED then
                rin.wen <= '1';
                rin.killing(x) <= '1';
                rin.faulting(x) <= '0';
                rin.waits(x) <= (others => '0');
                rin.rd_err(x) <= '0';
                rin.wr_err(x) <= '0';
              end if;

            when CMD_START =>
              if xs.state = TS_STOPPED then
                rin.wen <= '1';
                rin.rd_err(x) <= '0';
                rin.wr_err(x) <= '0';
                rin.clear(x) <= '1';
                rin.cmd_writes <= mask_of(word_pc_c) or mask_of(word_ptr_c);
                rin.state <= ST_CMD_WRITE;
              end if;
          end case;
        end if;

      when ST_CMD_WRITE =>
        rin.wen <= '1';
        rin.wword <= first_word(r.cmd_writes);
        if first_word(r.cmd_writes) = word_pc_c then
          rin.wdata <= std_ulogic_vector(r.cmd.pc);
        else
          rin.wdata <= (others => '0');
        end if;
        rin.cmd_writes <= without(r.cmd_writes, first_word(r.cmd_writes));
        if without(r.cmd_writes, first_word(r.cmd_writes)) = (word_mask_t'range => '0') then
          rin.state <= ST_RETIRE;
        end if;

      when ST_LOAD =>
        if r.loaded(word_pc_c) = '1' then
          rin.state <= ST_SWITCH;
        end if;

      when ST_SWITCH =>
        rin.ipos <= to_signed(0, 6) - signed(resize(r.w.pc(bus_l2_c-1 downto 0), 6));
        rin.fetch.valid <= '1';
        if r.mgr_live then
          rin.fetch.manager <= '1';
        else
          rin.fetch.manager <= '0';
        end if;
        rin.fetch.channel <= to_unsigned(r.cur, channel_t'length);
        rin.fetch.addr <= r.w.pc(31 downto bus_l2_c) & to_unsigned(0, bus_l2_c);
        rin.state <= ST_FETCH;

      when ST_FETCH =>
        if fetch_ready_i = '1' then
          rin.fetch.valid <= '0';
          rin.state <= ST_FETCH_WAIT;
        end if;

      when ST_FETCH_WAIT =>
        if fetch_i.valid = '1' then
          if fetch_i.error = '1' then
            rin.w.s.fault(f_fetch_c) <= '1';
            rin.w.s.state <= TS_FAULT_COMPLETING;
            rin.state <= ST_RETIRE;
          else
            rin.ibuf <= ibuf_append(r.ibuf, r.ipos, fetch_i.data(0 to bus_bytes_c-1));
            rin.ipos <= r.ipos + bus_bytes_c;
            rin.state <= ST_FETCH_CHECK;
          end if;
        end if;

      when ST_FETCH_CHECK =>
        rin.npc <= r.w.pc + instruction_length(r.ibuf(0));
        rin.op <= decode_operand(op, b1);
        rin.allowed <= thread_allows(decode_operand(op, b1), r.mgr_live);
        rin.cond_ok <= op(0) = '0' or op(1) = r.w.s.req_burst;
        rin.periph_bad <= operand >= peripheral_count_c;
        rin.event_bad <= operand >= event_count_c;
        rin.event_waited <= waited(r.waits, operand) or is_set(r.mgr_waits, operand);
        if r.ipos < signed(resize(instruction_length(r.ibuf(0)), 6)) then
          rin.fetch.valid <= '1';
          rin.fetch.addr <= r.fetch.addr + bus_bytes_c;
          rin.state <= ST_FETCH;
        elsif r.loaded(0 to load_words_c-1) = (0 to load_words_c-1 => '1') then
          rin.state <= ST_DECODE;
        end if;

      when ST_DECODE =>
        rin.state <= ST_RETIRE;

        if not r.allowed then
          rin.w.s.fault(f_undef_c) <= '1';
          rin.w.s.state <= TS_FAULT_COMPLETING;
        else
          case r.op is
            when OP_UNDEF =>
              rin.w.s.fault(f_undef_c) <= '1';
              rin.w.s.state <= TS_FAULT_COMPLETING;

            when OP_INVALID =>
              rin.w.s.fault(f_operand_c) <= '1';
              rin.w.s.state <= TS_FAULT_COMPLETING;

            when OP_END =>
              rin.w.pc <= r.npc;
              rin.w.s.state <= TS_COMPLETING;

            when OP_KILL =>
              rin.w.pc <= r.npc;
              rin.w.s.state <= TS_KILLING;

            when OP_NOP =>
              rin.w.pc <= r.npc;

            when OP_RMB =>
              rin.w.pc <= r.npc;
              rin.w.s.state <= TS_BARRIER;
              rin.w.s.barrier <= BARRIER_READ;

            when OP_WMB =>
              rin.w.pc <= r.npc;
              rin.w.s.state <= TS_BARRIER;
              rin.w.s.barrier <= BARRIER_WRITE;

            when OP_LP =>
              rin.w.pc <= r.npc;
              rin.dirty(word_loop_c) <= '1';
              if op(1) = '0' then
                rin.w.lc0 <= unsigned(b1);
              else
                rin.w.lc1 <= unsigned(b1);
              end if;

            when OP_LPEND =>
              if not r.cond_ok or lc = 0 then
                rin.w.pc <= r.npc;
              else
                rin.w.pc <= r.w.pc - unsigned(b1);
                rin.dirty(word_loop_c) <= '1';
                if op(2) = '0' then
                  rin.w.lc0 <= r.w.lc0 - 1;
                else
                  rin.w.lc1 <= r.w.lc1 - 1;
                end if;
              end if;

            when OP_LPEND_FOREVER =>
              if r.w.s.req_last = '1' then
                rin.w.pc <= r.npc;
              else
                rin.w.pc <= r.w.pc - unsigned(b1);
              end if;

            when OP_WFP =>
              if r.periph_bad then
                rin.w.s.fault(f_operand_c) <= '1';
                rin.w.s.state <= TS_FAULT_COMPLETING;
              else
                rin.w.pc <= r.npc;
                rin.w.s.state <= TS_WFP;
                rin.w.s.wakeup <= unsigned(b1(7 downto 3));
                rin.w.s.waited <= '1';
                -- Set for burst and periph, as the Zynq-7000's DMA-330
                rin.w.s.wfp_burst <= op(1) or op(0);
                rin.w.s.wfp_periph <= op(0);
              end if;

            when OP_FLUSHP =>
              if r.periph_bad then
                rin.w.s.fault(f_operand_c) <= '1';
                rin.w.s.state <= TS_FAULT_COMPLETING;
              else
                rin.w.pc <= r.npc;
                rin.flush.valid <= '1';
                rin.flush.periph <= unsigned(b1(7 downto 3));
                rin.flush.atype <= datype_flush_c;
                rin.state <= ST_FLUSH;
              end if;

            when OP_SEV =>
              if r.event_bad then
                rin.w.s.fault(f_operand_c) <= '1';
                rin.w.s.state <= TS_FAULT_COMPLETING;
              else
                rin.w.pc <= r.npc;
                for e in 0 to event_count_c-1
                loop
                  if operand = to_unsigned(e, 5) then
                    if irq_enable_i(e) = '1' then
                      rin.active(e) <= '1';
                    elsif r.event_waited then
                      for c in 0 to channel_count_c-1
                      loop
                        rin.waits(c)(e) <= '0';
                      end loop;
                      rin.mgr_waits(e) <= '0';
                    else
                      rin.active(e) <= '1';
                    end if;
                  end if;
                end loop;
              end if;

            when OP_WFE =>
              if r.event_bad then
                rin.w.s.fault(f_operand_c) <= '1';
                rin.w.s.state <= TS_FAULT_COMPLETING;
              elsif is_set(pending, operand) then
                rin.w.pc <= r.npc;
                rin.w.s.waited <= '0';
                for e in 0 to event_count_c-1
                loop
                  if operand = to_unsigned(e, 5) then
                    rin.active(e) <= '0';
                  end if;
                end loop;
              else
                rin.w.pc <= r.npc;
                rin.w.s.state <= TS_WFE;
                rin.w.s.wakeup <= operand;
                rin.w.s.waited <= '1';
                for e in 0 to event_count_c-1
                loop
                  if operand = to_unsigned(e, 5) then
                    if r.mgr_live then
                      rin.mgr_waits(e) <= '1';
                    else
                      rin.waits(r.cur)(e) <= '1';
                    end if;
                  end if;
                end loop;
              end if;

            when OP_GO =>
              if unsigned(b1(2 downto 0)) >= channel_count_c then
                rin.w.s.fault(f_operand_c) <= '1';
                rin.w.s.state <= TS_FAULT_COMPLETING;
              else
                rin.w.pc <= r.npc;
                rin.cmd.kind <= CMD_START;
                rin.cmd.channel <= unsigned(b1(2 downto 0));
                rin.cmd.pc <= imm32(r.ibuf);
                rin.state <= ST_CMD_READ;
              end if;

            when OP_ADDH =>
              rin.w.pc <= r.npc;
              if op(1) = '0' then
                rin.w.sar <= r.w.sar + imm16(r.ibuf);
                rin.dirty(word_sar_c) <= '1';
              else
                rin.w.dar <= r.w.dar + imm16(r.ibuf);
                rin.dirty(word_dar_c) <= '1';
              end if;

            when OP_ADNH =>
              rin.w.pc <= r.npc;
              if op(1) = '0' then
                rin.w.sar <= r.w.sar + (x"ffff" & imm16(r.ibuf));
                rin.dirty(word_sar_c) <= '1';
              else
                rin.w.dar <= r.w.dar + (x"ffff" & imm16(r.ibuf));
                rin.dirty(word_dar_c) <= '1';
              end if;

            when OP_MOV =>
              case b1(2 downto 0) is
                when "000" =>
                  rin.w.pc <= r.npc;
                  rin.w.sar <= imm32(r.ibuf);
                  rin.dirty(word_sar_c) <= '1';
                when "010" =>
                  rin.w.dar <= imm32(r.ibuf);
                  rin.dirty(word_dar_c) <= '1';
                  rin.w.pc <= r.npc;
                  if imm32(r.ibuf)(bus_l2_c-1 downto 0) /= r.w.dar(bus_l2_c-1 downto 0) then
                    rin.w.s.state <= TS_BARRIER;
                    rin.w.s.barrier <= BARRIER_DISCARD;
                  end if;
                when "001" =>
                  -- ibuf(2) holds CCR[7:0], ibuf(3) CCR[15:8],
                  -- ibuf(4) CCR[23:16], ibuf(5) CCR[31:24].  The
                  -- swap size is bounded by the larger burst size, as
                  -- the Zynq-7000's DMA-330 does.  Bit 31 is not
                  -- stored.
                  if unsigned(r.ibuf(2)(3 downto 1)) > bus_l2_c
                    or unsigned(r.ibuf(4)(1 downto 0) & r.ibuf(3)(7)) > bus_l2_c
                    or (r.ibuf(5)(6 downto 4) /= "000"
                        and (not endian_swap_c
                             or (unsigned(r.ibuf(5)(6 downto 4))
                                 > unsigned(r.ibuf(4)(1 downto 0) & r.ibuf(3)(7))
                                 and unsigned(r.ibuf(5)(6 downto 4))
                                 > unsigned(r.ibuf(2)(3 downto 1))))) then
                    rin.w.s.fault(f_operand_c) <= '1';
                    rin.w.s.state <= TS_FAULT_COMPLETING;
                  else
                    rin.w.pc <= r.npc;
                    rin.w.ccr <= '0' & std_ulogic_vector(imm32(r.ibuf)(30 downto 0));
                    rin.dirty(word_ccr_c) <= '1';
                    if ccr_discontinuity(r.w.ccr, std_ulogic_vector(imm32(r.ibuf))) then
                      rin.w.s.state <= TS_BARRIER;
                      rin.w.s.barrier <= BARRIER_DISCARD;
                    end if;
                  end if;
                when others =>
                  -- decode_operand made it OP_INVALID
                  null;
              end case;

            when OP_LD | OP_ST | OP_STZ | OP_LDP | OP_STP =>
              if (r.op = OP_LDP or r.op = OP_STP)
                and r.periph_bad then
                rin.w.s.fault(f_operand_c) <= '1';
                rin.w.s.state <= TS_FAULT_COMPLETING;
              elsif r.op /= OP_STZ and not r.cond_ok then
                rin.w.pc <= r.npc;
              else
                rin.state <= ST_XFER_SIZE;
                rin.xfer.channel <= to_unsigned(r.cur, channel_t'length);
                rin.xfer.periph <= unsigned(b1(7 downto 3));
                rin.xfer.ack_burst <= op(1);
                if r.op = OP_LDP or r.op = OP_STP then
                  rin.xfer.ack <= '1';
                else
                  rin.xfer.ack <= '0';
                end if;
                if r.op = OP_STZ then
                  rin.x_zero <= '1';
                else
                  rin.x_zero <= '0';
                end if;

                if r.op = OP_LD or r.op = OP_LDP then
                  rin.x_store <= '0';
                  rin.x_incr <= r.w.ccr(0);
                  rin.x_size_l2 <= unsigned(r.w.ccr(3 downto 1));
                  rin.x_addr <= r.w.sar;
                  rin.xfer.prot <= r.w.ccr(10 downto 8);
                  rin.xfer.cache <= '0' & r.w.ccr(13 downto 11);
                  if op(0) = '1' and op(1) = '0' then
                    rin.x_len_m1 <= (others => '0');
                  else
                    rin.x_len_m1 <= unsigned(r.w.ccr(7 downto 4));
                  end if;
                else
                  rin.x_store <= '1';
                  rin.x_incr <= r.w.ccr(14);
                  rin.x_size_l2 <= unsigned(r.w.ccr(17 downto 15));
                  rin.x_addr <= r.w.dar;
                  rin.xfer.prot <= r.w.ccr(24 downto 22);
                  rin.xfer.cache <= r.w.ccr(27) & '0' & r.w.ccr(26 downto 25);
                  if endian_swap_c then
                    rin.xfer.swap_l2 <= unsigned(r.w.ccr(30 downto 28));
                  else
                    rin.xfer.swap_l2 <= (others => '0');
                  end if;
                  if r.op /= OP_STZ and op(0) = '1' and op(1) = '0' then
                    rin.x_len_m1 <= (others => '0');
                  else
                    rin.x_len_m1 <= unsigned(r.w.ccr(21 downto 18));
                  end if;
                end if;
              end if;
          end case;
        end if;

      when ST_XFER_SIZE =>
        rin.x_lenbytes <= shift_left(resize(r.x_len_m1, 9), to_integer(r.x_size_l2));
        rin.x_head <= size_bytes(r.x_size_l2)
                      - resize(r.x_addr(max_bus_bytes_l2_c-1 downto 0) and size_mask(r.x_size_l2), 5);
        if r.x_incr = '0'
          and (r.x_addr(max_bus_bytes_l2_c-1 downto 0) and size_mask(r.x_size_l2)) /= 0 then
          rin.w.s.fault(f_operand_c) <= '1';
          rin.w.s.state <= TS_FAULT_COMPLETING;
          rin.state <= ST_RETIRE;
        else
          rin.state <= ST_XFER_BYTES;
        end if;

      when ST_XFER_BYTES =>
        rin.x_bytes <= r.x_lenbytes + r.x_head;
        rin.state <= ST_XFER_CHECK;

      when ST_XFER_CHECK =>
        if r.x_incr = '1' then
          rin.x_addr_next <= r.x_addr + r.x_bytes;
        else
          rin.x_addr_next <= r.x_addr;
        end if;
        rin.x_released <= ptr_wrap(released_i(r.cur), cap_l2_c);
        if r.x_store = '0' then
          rin.x_end <= ptr_wrap(r.w.ld_ptr + r.x_bytes, cap_l2_c);
        else
          rin.x_end <= ptr_wrap(r.w.st_ptr + r.x_bytes, cap_l2_c);
        end if;

        if r.x_zero = '0' and too_big(r.x_bytes) then
          rin.w.s.fault(f_mfifo_c) <= '1';
          rin.w.s.state <= TS_FAULT_COMPLETING;
          rin.state <= ST_RETIRE;
        else
          rin.state <= ST_XFER_SPACE;
        end if;

      when ST_XFER_SPACE =>
        -- Read pointer is sampled a state early: it only moves
        -- forward, the estimate of room is conservative.
        rin.x_room <= ptr_wrap(r.x_end - r.x_released, cap_l2_c);
        rin.x_avail <= ptr_wrap(r.w.ld_ptr - r.x_end, cap_l2_c);
        rin.x_drained <= r.w.st_ptr = r.x_released;
        rin.x_pushed <= ptr_wrap(pushed_i(r.cur) - r.x_end, cap_l2_c);
        rin.x_poison <= ptr_wrap(r.x_end - poison_i(r.cur), cap_l2_c);
        rin.x_poisoned <= poisoned_i(r.cur) = '1';
        rin.state <= ST_XFER_ROOM;

      when ST_XFER_ROOM =>
        if r.x_store = '0' and not fits(r.x_room) then
          if r.x_drained then
            -- No queued store can make room anymore
            rin.w.s.fault(f_mfifo_c) <= '1';
            rin.w.s.state <= TS_FAULT_COMPLETING;
          end if;
          rin.state <= ST_RETIRE;
        elsif r.x_store = '1' and r.x_zero = '0' and ptr_negative(r.x_avail, cap_l2_c) then
          rin.w.s.fault(f_st_data_c) <= '1';
          rin.w.s.state <= TS_FAULT_COMPLETING;
          rin.state <= ST_RETIRE;
        elsif failed_store_fault_c
          and r.x_store = '1' and r.x_zero = '0' and ptr_negative(r.x_pushed, cap_l2_c) then
          -- Its data is not loaded yet: waits for the loads, then
          -- executes again
          rin.w.s.state <= TS_BARRIER;
          rin.w.s.barrier <= BARRIER_DATA;
          rin.state <= ST_RETIRE;
        elsif failed_store_fault_c
          and r.x_store = '1' and r.x_zero = '0' and r.x_poisoned
          and r.x_poison /= 0 and not ptr_negative(r.x_poison, cap_l2_c) then
          -- It would store bytes a failed load brought: it faults
          -- instead, past it, its transfer error showing in FTR, as the
          -- Zynq's DMA-330 does
          rin.w.pc <= r.npc;
          rin.w.s.state <= TS_FAULT_COMPLETING;
          rin.state <= ST_RETIRE;
        else
          rin.xfer.valid <= '1';
          rin.xfer.addr <= r.x_addr;
          rin.xfer.size_l2 <= r.x_size_l2;
          rin.xfer.len_m1 <= r.x_len_m1;
          rin.xfer.incr <= r.x_incr;
          rin.xfer.bytes <= r.x_bytes;
          rin.xfer.zero <= r.x_zero;
          rin.w.pc <= r.npc;
          if r.x_store = '0' then
            rin.w.sar <= r.x_addr_next;
            rin.w.ld_ptr <= r.x_end;
            rin.dirty(word_sar_c) <= '1';
            rin.dirty(word_ptr_c) <= '1';
          else
            rin.w.dar <= r.x_addr_next;
            rin.dirty(word_dar_c) <= '1';
            if r.x_zero = '0' then
              rin.w.st_ptr <= r.x_end;
              rin.dirty(word_ptr_c) <= '1';
            end if;
          end if;
          rin.state <= ST_XFER_WAIT;
        end if;

      when ST_XFER_WAIT =>
        if (r.x_store = '0' and load_ready_i = '1')
          or (r.x_store = '1' and store_ready_i = '1') then
          rin.xfer.valid <= '0';
          rin.state <= ST_RETIRE;
        end if;

      when ST_FLUSH =>
        if flush_grant_i = '1' then
          rin.flush.valid <= '0';
          rin.state <= ST_RETIRE;
        end if;

      when ST_RETIRE =>
        if not r.live then
          -- A debug instruction executed
          rin.dbg.valid <= '0';
          rin.state <= ST_SCAN;
        elsif r.mgr_live then
          rin.live <= false;
          rin.mgr_live <= false;
          rin.mgr_turn <= false;
          rin.mgr_pc <= r.w.pc;
          rin.mgr <= r.w.s;
          case r.w.s.state is
            when TS_FAULT_COMPLETING =>
              rin.mgr.state <= TS_FAULTING;
            when TS_COMPLETING | TS_KILLING =>
              rin.mgr.state <= TS_STOPPED;
            when others =>
              null;
          end case;
          rin.state <= ST_SCAN;
        elsif r.load_next = load_words_c and r.dtag.kind /= READ_LOAD then
          -- Once every context word is read, writes back the PC, the
          -- changed words and the scheduling word, last.
          rin.dirty <= r.dirty or mask_of(word_pc_c) or mask_of(word_sched_c);
          rin.state <= ST_WRITE_BACK;
        end if;

      when ST_WRITE_BACK =>
        rin.wen <= '1';
        rin.wthread <= r.cur;
        rin.wword <= wb;
        rin.wdata <= context_word(r.w, wb);
        rin.dirty <= without(r.dirty, wb);
        if wb = word_sched_c then
          rin.live <= false;
          rin.mgr_turn <= true;
          rin.scan <= next_channel(r.cur);
          rin.state <= ST_SCAN;
          if r.w.s.state = TS_FAULT_COMPLETING then
            rin.faulting(r.cur) <= '1';
          end if;
          if r.w.s.state = TS_KILLING then
            rin.killing(r.cur) <= '1';
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    debug_ready_o <= not r.dbg.valid;
    status_ready_o <= '1';
    status_raddr_s <= ctx_addr(0, status_word(r.sreq.reg));
    for c in 0 to channel_count_c-1
    loop
      if r.sreq.channel = to_unsigned(c, channel_t'length) then
        status_raddr_s <= ctx_addr(c, status_word(r.sreq.reg));
      end if;
    end loop;
    status_o <= r.sresp;

    manager_o.state <= state_code(r.mgr.state);
    manager_o.wakeup <= (others => '0');
    if r.mgr.waited = '1' then
      manager_o.wakeup <= r.mgr.wakeup;
    end if;
    manager_o.pc <= r.mgr_pc;
    manager_o.fault <= fault_register(r.mgr.fault);
    faulting_o <= r.faulting;
    events_o <= r.active;

    ctx_raddr_s <= ctx_addr(r.rtag.thread, r.rtag.word);
    ctx_waddr_s <= ctx_addr(r.wthread, r.wword);
    ctx_wen_s(0) <= r.wen;
    ctx_wdata_s <= r.wdata;

    irq_abort_o <= '0';
    if r.faulting /= (r.faulting'range => '0') or r.mgr.state = TS_FAULTING then
      irq_abort_o <= '1';
    end if;
    abort_o <= r.killing;
    clear_o <= r.clear;
    pop_o <= r.pop;
    flush_o <= r.flush;
    fetch_o <= r.fetch;

    load_o <= r.xfer;
    load_o.valid <= r.xfer.valid and not r.x_store;
    store_o <= r.xfer;
    store_o.valid <= r.xfer.valid and r.x_store;
  end process;

  mealy: process(r, irq_enable_i) is
  begin
    irq_o <= r.active and irq_enable_i;
  end process;

end architecture;
