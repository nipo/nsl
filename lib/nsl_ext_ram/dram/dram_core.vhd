library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_logic, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_math.arith.all;
use nsl_logic.bool.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;

-- Accesses are taken in, scheduled and answered by three parts running
-- side by side, so that a run of accesses landing in an open row costs
-- one column command each rather than a visit to a state per step.
--
-- * a command queue and a write payload queue take the user side in,
--   each with its own handshake, so the cycle a burst is commanded on
--   can also carry a payload cycle of the burst before it;
-- * the scheduler picks one action per cycle out of the registers
--   alone, and a column command it picks is not held up by the answer
--   to the one before;
-- * read answers land in a queue of their own and leave it while later
--   reads are still on the bus.
--
-- The pick itself reads one register field, `sched`, which holds the
-- head of the queue decoded and every delay it has to clear already
-- compared.  That field is written from the next state of the
-- registers it summarises, worked out from the registers alone: an
-- access arriving on the user side is scheduled off the slot it was
-- written into rather than off the wires it arrived on, so the logic
-- that offers it and the logic that judges it never share a cycle.
--
-- The whole burst is still buffered either way round: no DRAM tolerates
-- a data bus that stalls inside a burst, so a write goes out only once
-- its payload is entirely in, and a read is announced only once there
-- is room for its answer.
--
-- Commands go out on phase 0 only, and every delay is rounded up to a
-- whole controller cycle.  On a part with several phases per cycle that
-- leaves command bandwidth and a little latency on the table, but never
-- breaks a constraint.
entity dram_core is
  generic(
    part_c: dram_part_t;
    timing_c: dram_timing_t;
    dfi_config_c: config_t;
    script_c: init_script_t;
    burst_length_l2_c: natural;
    keep_row_open_c: boolean := true;
    -- Read bursts that may be announced to the PHY at once.  A PHY
    -- that arms one capture at a time takes 1 and nothing else.
    read_ahead_c: positive := 1;
    -- Whether the PHY can have two write bursts in the air together.
    -- One that lays a whole burst out from the command it belongs to
    -- cannot, and column commands are then spaced by the time the
    -- burst spends on the wire rather than by tCCD.
    write_overlap_c: boolean := false
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    cmd_i: in cmd_t;
    cmd_o: out cmd_ack_t;
    wdata_i: in wdata_t;
    wdata_o: out wdata_ack_t;
    rdata_o: out rdata_t;
    rdata_i: in rdata_ack_t;

    ready_o: out std_ulogic;

    dfi_o: out master_t;
    dfi_i: in slave_t
    );
end entity;

architecture beh of dram_core is

  constant l_c: layout_t := layout(part_c, dfi_config_c, burst_length_l2_c);
  constant phase_c: positive := dfi_config_c.phase_count;
  constant bank_count_c: natural := 2 ** part_c.bank_count_l2;
  -- Controller cycles one burst holds the data bus for
  constant burst_c: natural := l_c.burst_cycle_count;

  -- Datasheet delays, rounded up to controller cycles.
  constant rcd_c: natural := controller_ticks(timing_c.rcd, phase_c);
  constant ras_c: natural := controller_ticks(timing_c.ras, phase_c);
  constant rc_c: natural := controller_ticks(timing_c.rc, phase_c);
  constant rp_c: natural := controller_ticks(timing_c.rp, phase_c);
  constant rrd_c: natural := controller_ticks(timing_c.rrd, phase_c);
  constant rtp_c: natural := controller_ticks(timing_c.rtp, phase_c);
  constant rfc_c: natural := controller_ticks(timing_c.rfc, phase_c);
  constant refi_c: natural := timing_c.refi / phase_c;

  -- Write recovery and write to read are counted from the last data
  -- word on the bus.  The PHY places the burst CAS write latency after
  -- the command, and it spans this many memory ticks.
  constant write_span_ck_c: natural
    := l_c.burst_beat_count / dfi_config_c.edge_count;
  constant write_end_ck_c: natural
    := timing_c.cwl + write_span_ck_c - 1;
  constant wr_c: natural
    := controller_ticks(write_end_ck_c + timing_c.wr, phase_c);
  constant wtr_c: natural
    := controller_ticks(write_end_ck_c + timing_c.wtr, phase_c);

  -- Column to column, which is also how long a burst holds the data
  -- bus.  Back to back column commands are what a row hit costs, so
  -- this is the delay the pipeline runs at.
  constant ccd_c: natural := nsl_math.arith.max(
    controller_ticks(timing_c.ccd, phase_c), burst_c);

  -- Write to write.  A burst is still on the wire CAS write latency
  -- after the command that asked for it, so a PHY holding one burst
  -- at a time is only free again once the whole of it has gone out.
  -- On a part whose write latency is zero this is tCCD anyway, which
  -- is why a single data rate bus writes back to back either way.
  function write_to_write return natural
  is
  begin
    if write_overlap_c then
      return ccd_c;
    end if;

    return nsl_math.arith.max(
      ccd_c,
      controller_ticks(timing_c.cwl + write_span_ck_c, phase_c));
  end function;

  constant wtw_c: natural := write_to_write;

  constant age_max_c: natural := nsl_math.arith.max(
    nsl_math.arith.max(rcd_c, nsl_math.arith.max(ras_c, rc_c)),
    nsl_math.arith.max(rp_c, nsl_math.arith.max(rrd_c,
      nsl_math.arith.max(wr_c, nsl_math.arith.max(wtr_c,
        nsl_math.arith.max(rtp_c, rfc_c))))));

  constant age_width_c: natural := log2(age_max_c + 1);
  constant refresh_width_c: natural := log2(refi_c + 1);
  constant init_width_c: natural := log2(longest_delay(script_c) + 1);
  constant step_max_c: natural := script_c.length - 1;

  -- Accesses taken in ahead of the one being scheduled.  The head is
  -- decoded a cycle before it is picked, so sustaining a column
  -- command per cycle takes one slot for the access being picked, one
  -- for the access already decoded behind it, and one for the access
  -- arriving into the slot the first is leaving.  At two the queue
  -- settles one short of that and every other cycle goes empty.
  constant acc_depth_c: natural := 3;
  constant wdata_depth_c: natural := 2 * burst_c;
  -- Room for every answer that has been asked for, plus one burst
  -- being drained, so an announced read never has to wait for
  -- somewhere to land.
  constant rdata_depth_c: natural := (read_ahead_c + 1) * burst_c;
  constant owed_max_c: natural := read_ahead_c * burst_c;

  subtype age_t is unsigned(age_width_c - 1 downto 0);
  type age_vector is array (natural range <>) of age_t;
  constant age_saturated_c: age_t := (others => '1');

  subtype row_t is unsigned(l_c.row_width - 1 downto 0);
  type row_vector is array (natural range <>) of row_t;

  subtype bank_mask_t is std_ulogic_vector(0 to bank_count_c - 1);
  type bank_flag_vector is array (0 to bank_count_c - 1) of boolean;

  type address_vector is array (natural range <>) of byte_address_t;

  subtype cycle_t is byte_string(0 to l_c.cycle_byte_count - 1);
  type cycle_vector is array (natural range <>) of cycle_t;
  subtype cycle_mask_t is std_ulogic_vector(0 to l_c.cycle_byte_count - 1);
  type cycle_mask_vector is array (natural range <>) of cycle_mask_t;

  type state_t is (
    ST_RESET,
    ST_INIT_ISSUE,
    ST_INIT_WAIT,
    ST_RUN,
    ST_REFRESH_PRECHARGE,
    ST_REFRESH_PRECHARGE_ISSUE,
    ST_REFRESH
    );

  -- What the scheduler puts on the command bus this cycle.  It is
  -- derived from the registers alone, so the transition process and
  -- the output process reach the same answer without a signal between
  -- them.
  type action_t is (
    ACT_NONE,
    ACT_CLOSE,
    ACT_PRECHARGE,
    ACT_ACTIVATE,
    ACT_WRITE,
    ACT_READ
    );

  -- The ground the pick is made on, held one cycle ahead of the pick.
  -- The head of the command queue arrives here decoded and the delays
  -- it has to clear arrive compared, so picking is a function of
  -- single bits and nothing between the access queue and a bank stamp
  -- has to settle inside one cycle.
  --
  -- Every field is written from the next state of what it summarises,
  -- and that next state is worked out from the registers alone: no
  -- handshake of the user side and no answer of the PHY reaches this
  -- record on the cycle it is written.  Where the value the pick wants
  -- does depend on what the user side did, the ground carries one
  -- field per outcome and the pick chooses between them off a
  -- registered bit -- the arriving payload cycle below.
  type sched_t is
  record
    -- The access at the head of the queue, decoded
    bank: natural range 0 to bank_count_c - 1;
    bank_sel: bank_mask_t;
    row: row_t;
    column: unsigned(max_address_width_c - 1 downto 0);
    write: std_ulogic;
    valid: std_ulogic;

    -- What the bank that access wants holds
    active: std_ulogic;
    hit: std_ulogic;

    -- A burst is still putting its payload out, or a refresh is due,
    -- so nothing may be started at all
    blocked: std_ulogic;

    -- Whether the delays each action has to clear are clear
    activate_ok: std_ulogic;
    precharge_ok: std_ulogic;
    -- Write ground, the second with the payload cycle that arrived on
    -- the cycle this ground was written counted in.
    write_ok: std_ulogic;
    write_ok_arrived: std_ulogic;
    -- Read ground.  An answer landing on the cycle the read would be
    -- announced on is not counted: it frees the PHY on the cycle after
    -- the one this ground was written for, and it is that cycle's
    -- ground that carries it.
    read_ok: std_ulogic;

    -- Ground for closing the bank an access has just left open under
    -- a policy that closes it
    close_sel: bank_mask_t;
    close_ok: std_ulogic;
  end record;

  type regs_t is
  record
    state: state_t;

    step: natural range 0 to max_script_step_count_c - 1;
    init_left: unsigned(init_width_c - 1 downto 0);

    -- Accesses taken in, oldest at acc_issue
    acc_address: address_vector(0 to acc_depth_c - 1);
    acc_write: std_ulogic_vector(0 to acc_depth_c - 1);
    acc_fill: natural range 0 to acc_depth_c - 1;
    acc_issue: natural range 0 to acc_depth_c - 1;
    acc_count: natural range 0 to acc_depth_c;

    -- Write payload waiting to go out, oldest cycle at wdata_issue
    wdata: cycle_vector(0 to wdata_depth_c - 1);
    wmask: cycle_mask_vector(0 to wdata_depth_c - 1);
    wdata_fill: natural range 0 to wdata_depth_c - 1;
    wdata_issue: natural range 0 to wdata_depth_c - 1;
    wdata_count: natural range 0 to wdata_depth_c;
    -- Cycles of the burst under way still to put on the data bus
    wdata_left: natural range 0 to burst_c;
    -- A payload cycle was taken in on the cycle before this one, so
    -- the write ground to read is the one that counts it
    wdata_arrived: std_ulogic;

    -- Read answers waiting to leave, oldest at rdata_drain
    rdata: cycle_vector(0 to rdata_depth_c - 1);
    rdata_fill: natural range 0 to rdata_depth_c - 1;
    rdata_drain: natural range 0 to rdata_depth_c - 1;
    rdata_count: natural range 0 to rdata_depth_c;
    -- Cycles the part still owes for reads already announced
    rdata_owed: natural range 0 to owed_max_c;
    -- Cycles the announcement of the read under way is still held for
    rddata_en_left: natural range 0 to burst_c;

    -- Cycles before the data bus is free for another column command
    column_busy: natural range 0 to wtw_c;

    bank_active: bank_mask_t;
    bank_row: row_vector(0 to bank_count_c - 1);
    since_activate: age_vector(0 to bank_count_c - 1);
    since_precharge: age_vector(0 to bank_count_c - 1);
    since_any_activate: age_t;
    since_write: age_t;
    since_read_command: age_t;
    since_refresh: age_t;
    write_bank: unsigned(l_c.bank_width - 1 downto 0);
    read_bank: unsigned(l_c.bank_width - 1 downto 0);

    -- Bank an access has just left open under a policy that closes it
    close_valid: std_ulogic;
    close_bank: natural range 0 to bank_count_c - 1;

    refresh_left: unsigned(refresh_width_c - 1 downto 0);
    refresh_due: std_ulogic;

    sched: sched_t;

    ready: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function older_than(value: age_t; bound: natural) return boolean
  is
  begin
    return to_integer(value) >= bound;
  end function;

  -- Every stamp ages by one cycle and stops at its saturation point;
  -- comparisons are against delays that never reach it.
  function aged(value: age_t) return age_t
  is
  begin
    if value = age_saturated_c then
      return value;
    end if;

    return value + 1;
  end function;

  function next_index(index, depth: natural) return natural
  is
  begin
    if index = depth - 1 then
      return 0;
    end if;

    return index + 1;
  end function;

  -- Where in the row an access lands, as the part wants it on the
  -- address bus.  The low bits of the column are the burst order and
  -- the part supplies them itself.
  function column_address(address: byte_address_t) return unsigned
  is
    variable ret: unsigned(max_address_width_c - 1 downto 0);
  begin
    ret := resize(column_of(l_c, address), max_address_width_c);

    if part_c.generation = DRAM_SDR or part_c.generation = DRAM_DDR then
      -- A10 doubles as the auto precharge flag and has to stay clear
      ret(10) := '0';
    end if;

    return ret;
  end function;

  function may_activate(rp_ok, rc_ok: boolean;
                        since_any_activate: age_t) return boolean
  is
  begin
    return rp_ok and rc_ok and older_than(since_any_activate, rrd_c);
  end function;

  -- A row closes once it has served tRAS, once the write recovery and
  -- the read to precharge delay of whatever this bank last carried
  -- have run out, and once no answer is still on its way back.
  function may_precharge(bank: natural;
                         ras_ok: boolean;
                         write_bank, read_bank: unsigned;
                         since_write, since_read_command: age_t;
                         owed: natural) return boolean
  is
    variable bank_v: unsigned(l_c.bank_width - 1 downto 0);
  begin
    bank_v := to_unsigned(bank, l_c.bank_width);

    return ras_ok
      and (write_bank /= bank_v or older_than(since_write, wr_c))
      and (read_bank /= bank_v or older_than(since_read_command, rtp_c))
      and owed = 0;
  end function;

  function may_write(rcd_ok: boolean;
                     column_busy, wdata_count, owed: natural) return boolean
  is
  begin
    return rcd_ok
      and column_busy = 0
      -- The payload is entirely in, so the data bus will not stall
      -- inside the burst.
      and wdata_count >= burst_c
      -- An answer still on its way back owns the data bus.
      and owed = 0;
  end function;

  function may_read(rcd_ok: boolean;
                    column_busy: natural;
                    since_write: age_t;
                    owed, rdata_count: natural) return boolean
  is
  begin
    return rcd_ok
      and column_busy = 0
      and older_than(since_write, wtr_c)
      -- The PHY has an announcement to spare, and the answer has
      -- somewhere to land whatever the user side does meanwhile.
      and owed + burst_c <= owed_max_c
      and rdata_count + owed + burst_c <= rdata_depth_c;
  end function;

  function next_action(r: regs_t) return action_t
  is
  begin
    if r.state /= ST_RUN then
      return ACT_NONE;
    end if;

    -- A burst still putting its payload out owns the cycle, and a
    -- refresh waits for the array to go quiet, so nothing new is
    -- started once one is due.
    if r.sched.blocked = '1' then
      return ACT_NONE;
    end if;

    if r.close_valid = '1' then
      if r.sched.close_ok = '1' then
        return ACT_CLOSE;
      end if;

      return ACT_NONE;
    end if;

    if r.sched.valid = '0' then
      return ACT_NONE;
    end if;

    if r.sched.hit = '1' then
      if r.sched.write = '1' then
        if r.wdata_arrived = '1' then
          if r.sched.write_ok_arrived = '1' then
            return ACT_WRITE;
          end if;
        elsif r.sched.write_ok = '1' then
          return ACT_WRITE;
        end if;
      elsif r.sched.read_ok = '1' then
        return ACT_READ;
      end if;
    elsif r.sched.active = '1' then
      if r.sched.precharge_ok = '1' then
        return ACT_PRECHARGE;
      end if;
    else
      if r.sched.activate_ok = '1' then
        return ACT_ACTIVATE;
      end if;
    end if;

    return ACT_NONE;
  end function;

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

  transition: process(r, cmd_i, wdata_i, rdata_i, dfi_i) is
    variable action_v: action_t;
    variable bank_v: natural range 0 to bank_count_c - 1;
    variable cmd_taken, wdata_taken, wdata_used: boolean;
    variable rdata_landed, rdata_left: boolean;
    variable column_done: boolean;
    variable all_closed: boolean;
    variable precharge_settled: boolean;
    variable refresh_ready, refresh_close: boolean;
    variable activate_now, precharge_now: boolean;

    -- Next state of everything the ground is read off, as far as the
    -- registers alone say it.  Taking the ground from these rather
    -- than from r is what makes holding it a cycle ahead free; leaving
    -- the user side's handshakes out of them is what keeps the cycle
    -- that writes the ground clear of whatever computes those.
    variable bank_active_v: bank_mask_t;
    variable bank_row_v: row_vector(0 to bank_count_c - 1);
    variable since_activate_v: age_vector(0 to bank_count_c - 1);
    variable since_precharge_v: age_vector(0 to bank_count_c - 1);
    variable rcd_ok_v, ras_ok_v, rc_ok_v, rp_ok_v: bank_flag_vector;
    variable since_any_activate_v, since_write_v: age_t;
    variable since_read_command_v: age_t;
    variable write_bank_v, read_bank_v: unsigned(l_c.bank_width - 1 downto 0);
    variable column_busy_v: natural range 0 to wtw_c;
    variable wdata_count_v, wdata_count_g: natural range 0 to wdata_depth_c;
    variable wdata_left_v: natural range 0 to burst_c;
    variable rdata_count_v, rdata_count_g: natural range 0 to rdata_depth_c;
    variable rdata_owed_v: natural range 0 to owed_max_c;
    variable acc_count_v, acc_count_g: natural range 0 to acc_depth_c;
    variable acc_issue_v: natural range 0 to acc_depth_c - 1;
    variable close_valid_v: std_ulogic;
    variable close_bank_v: natural range 0 to bank_count_c - 1;
    variable refresh_due_v: std_ulogic;

    -- The access the head of the queue will hold next cycle, decoded
    variable head_v: byte_address_t;
    variable head_write_v: std_ulogic;
    variable head_bank_v: natural range 0 to bank_count_c - 1;
    variable head_row_v: row_t;
  begin
    rin <= r;

    rdata_landed := dfi_i.rddata_valid = '1' and r.rdata_owed /= 0;
    action_v := next_action(r);
    bank_v := r.sched.bank;
    column_done := action_v = ACT_WRITE or action_v = ACT_READ;

    cmd_taken := cmd_i.valid = '1'
                 and r.ready = '1'
                 and r.acc_count /= acc_depth_c;
    wdata_taken := wdata_i.valid = '1' and r.wdata_count /= wdata_depth_c;
    wdata_used := action_v = ACT_WRITE or r.wdata_left /= 0;
    rdata_left := rdata_i.ready = '1' and r.rdata_count /= 0;

    -- A refresh needs every bank idle, and closing them needs every
    -- open one to have served its tRAS on top of what the last access
    -- still owes the array.  The tRP that follows runs from the bank
    -- closed last, whichever that is, so it is the smallest stamp of
    -- the set that has to clear the delay.
    all_closed := true;
    precharge_settled := true;
    refresh_ready := older_than(r.since_write, wr_c)
                     and older_than(r.since_read_command, rtp_c)
                     and r.rdata_owed = 0;
    for b in 0 to bank_count_c - 1
    loop
      if not older_than(r.since_precharge(b), rp_c) then
        precharge_settled := false;
      end if;
      if r.bank_active(b) = '1' then
        all_closed := false;
        if not older_than(r.since_activate(b), ras_c) then
          refresh_ready := false;
        end if;
      end if;
    end loop;

    -- The refresh sequence closes the whole array in one command.
    refresh_close := r.state = ST_REFRESH_PRECHARGE
                     and not all_closed
                     and refresh_ready;

    -- What the scheduler picked takes effect on the very cycle the
    -- output process puts the command out: every stamp is therefore
    -- zero on the cycle after its own command, which is the
    -- convention every delay above is read in.
    for b in 0 to bank_count_c - 1
    loop
      activate_now := action_v = ACT_ACTIVATE and r.sched.bank_sel(b) = '1';
      precharge_now := (action_v = ACT_PRECHARGE
                        and r.sched.bank_sel(b) = '1')
                       or (action_v = ACT_CLOSE
                           and r.sched.close_sel(b) = '1')
                       or refresh_close;

      if activate_now then
        bank_active_v(b) := '1';
        bank_row_v(b) := r.sched.row;
        since_activate_v(b) := (others => '0');
      else
        if precharge_now then
          bank_active_v(b) := '0';
        else
          bank_active_v(b) := r.bank_active(b);
        end if;
        bank_row_v(b) := r.bank_row(b);
        since_activate_v(b) := aged(r.since_activate(b));
      end if;

      if precharge_now then
        since_precharge_v(b) := (others => '0');
      else
        since_precharge_v(b) := aged(r.since_precharge(b));
      end if;

      rcd_ok_v(b) := older_than(since_activate_v(b), rcd_c);
      ras_ok_v(b) := older_than(since_activate_v(b), ras_c);
      rc_ok_v(b) := older_than(since_activate_v(b), rc_c);
      rp_ok_v(b) := older_than(since_precharge_v(b), rp_c);
    end loop;

    if action_v = ACT_ACTIVATE then
      since_any_activate_v := (others => '0');
    else
      since_any_activate_v := aged(r.since_any_activate);
    end if;

    if action_v = ACT_WRITE then
      since_write_v := (others => '0');
      write_bank_v := to_unsigned(bank_v, l_c.bank_width);
    else
      since_write_v := aged(r.since_write);
      write_bank_v := r.write_bank;
    end if;

    if action_v = ACT_READ then
      since_read_command_v := (others => '0');
      read_bank_v := to_unsigned(bank_v, l_c.bank_width);
    else
      since_read_command_v := aged(r.since_read_command);
      read_bank_v := r.read_bank;
    end if;

    if action_v = ACT_WRITE then
      column_busy_v := wtw_c - 1;
    elsif action_v = ACT_READ then
      column_busy_v := ccd_c - 1;
    elsif r.column_busy /= 0 then
      column_busy_v := r.column_busy - 1;
    else
      column_busy_v := 0;
    end if;

    if action_v = ACT_WRITE then
      wdata_left_v := burst_c - 1;
    elsif r.wdata_left /= 0 then
      wdata_left_v := r.wdata_left - 1;
    else
      wdata_left_v := 0;
    end if;

    if column_done and not keep_row_open_c then
      close_valid_v := '1';
      close_bank_v := bank_v;
    else
      if action_v = ACT_CLOSE or refresh_close then
        close_valid_v := '0';
      else
        close_valid_v := r.close_valid;
      end if;
      close_bank_v := r.close_bank;
    end if;

    -- A refresh is asked for on a fixed interval.  The request stands
    -- until the sequence serving it is over, and the interval is
    -- restarted where the core goes ready so the first one falls a
    -- whole interval later.
    case r.state is
      when ST_RESET | ST_INIT_ISSUE | ST_INIT_WAIT =>
        refresh_due_v := '0';

      when ST_REFRESH =>
        if older_than(r.since_refresh, rfc_c) then
          refresh_due_v := '0';
        else
          refresh_due_v := r.refresh_due;
        end if;

      when others =>
        if r.refresh_left = 0 then
          refresh_due_v := '1';
        else
          refresh_due_v := r.refresh_due;
        end if;
    end case;

    if r.refresh_left = 0 then
      rin.refresh_left <= to_unsigned(refi_c, refresh_width_c);
    else
      rin.refresh_left <= r.refresh_left - 1;
    end if;

    rin.since_refresh <= aged(r.since_refresh);

    if action_v = ACT_READ then
      rin.rddata_en_left <= burst_c - 1;
    elsif r.rddata_en_left /= 0 then
      rin.rddata_en_left <= r.rddata_en_left - 1;
    end if;

    -- The user side is taken in whatever the scheduler is doing.  The
    -- two queues fill apart and are matched back up by order: payload
    -- cycles belong to the oldest write command that has not gone out.
    if cmd_taken then
      rin.acc_address(r.acc_fill) <= cmd_i.address;
      rin.acc_write(r.acc_fill) <= cmd_i.write;
      rin.acc_fill <= next_index(r.acc_fill, acc_depth_c);
    end if;

    if cmd_taken and not column_done then
      acc_count_v := r.acc_count + 1;
    elsif column_done and not cmd_taken then
      acc_count_v := r.acc_count - 1;
    else
      acc_count_v := r.acc_count;
    end if;

    -- What the queue holds next cycle once the arriving command is
    -- left out of it: an access is only ever scheduled off a slot
    -- that was written on an earlier cycle, so nothing the user side
    -- drives reaches the ground.
    if column_done then
      acc_count_g := r.acc_count - 1;
      acc_issue_v := next_index(r.acc_issue, acc_depth_c);
    else
      acc_count_g := r.acc_count;
      acc_issue_v := r.acc_issue;
    end if;

    head_v := r.acc_address(acc_issue_v);
    head_write_v := r.acc_write(acc_issue_v);

    head_bank_v := to_integer(bank_of(l_c, head_v));
    head_row_v := row_of(l_c, head_v);

    if wdata_taken then
      rin.wdata(r.wdata_fill) <= wdata_i.data(0 to l_c.cycle_byte_count - 1);
      rin.wmask(r.wdata_fill) <= wdata_i.mask(0 to l_c.cycle_byte_count - 1);
      rin.wdata_fill <= next_index(r.wdata_fill, wdata_depth_c);
    end if;

    if wdata_used then
      rin.wdata_issue <= next_index(r.wdata_issue, wdata_depth_c);
    end if;

    if wdata_taken and not wdata_used then
      wdata_count_v := r.wdata_count + 1;
    elsif wdata_used and not wdata_taken then
      wdata_count_v := r.wdata_count - 1;
    else
      wdata_count_v := r.wdata_count;
    end if;

    -- The same count with the arriving cycle left out.  The ground is
    -- written for both outcomes and the pick reads the one the
    -- registered arrival flag names, so the payload handshake is a
    -- multiplexer away from the decision instead of in front of the
    -- comparison that feeds it.
    if wdata_used then
      wdata_count_g := r.wdata_count - 1;
    else
      wdata_count_g := r.wdata_count;
    end if;

    -- Read answers land whether or not the user side is taking any,
    -- which is why the room for them was reserved before the read was
    -- announced.
    if rdata_landed then
      rin.rdata(r.rdata_fill)
        <= value(dfi_config_c, dfi_i.rddata)(0 to l_c.cycle_byte_count - 1);
      rin.rdata_fill <= next_index(r.rdata_fill, rdata_depth_c);
    end if;

    if rdata_left then
      rin.rdata_drain <= next_index(r.rdata_drain, rdata_depth_c);
    end if;

    -- An answer landing and the count it is taken off are clocked
    -- from the same edge but do not settle together, so both counts
    -- carry their own bound rather than relying on the pair.
    if rdata_landed and not rdata_left
      and r.rdata_count /= rdata_depth_c then
      rdata_count_v := r.rdata_count + 1;
    elsif rdata_left and not rdata_landed and r.rdata_count /= 0 then
      rdata_count_v := r.rdata_count - 1;
    else
      rdata_count_v := r.rdata_count;
    end if;

    -- The same count with the beat the user side is taking left in.
    -- Room for an answer is what this count is asked for, so counting
    -- the queue fuller than it will be holds a read back for a cycle
    -- at worst and never announces one there is no room for.
    if rdata_landed and r.rdata_count /= rdata_depth_c then
      rdata_count_g := r.rdata_count + 1;
    else
      rdata_count_g := r.rdata_count;
    end if;

    if rdata_landed and action_v = ACT_READ then
      rdata_owed_v := r.rdata_owed + burst_c - 1;
    elsif rdata_landed then
      rdata_owed_v := r.rdata_owed - 1;
    elsif action_v = ACT_READ then
      rdata_owed_v := r.rdata_owed + burst_c;
    else
      rdata_owed_v := r.rdata_owed;
    end if;

    rin.bank_active <= bank_active_v;
    rin.bank_row <= bank_row_v;
    rin.since_activate <= since_activate_v;
    rin.since_precharge <= since_precharge_v;
    rin.since_any_activate <= since_any_activate_v;
    rin.since_write <= since_write_v;
    rin.since_read_command <= since_read_command_v;
    rin.write_bank <= write_bank_v;
    rin.read_bank <= read_bank_v;
    rin.column_busy <= column_busy_v;
    rin.wdata_count <= wdata_count_v;
    rin.wdata_left <= wdata_left_v;
    rin.wdata_arrived <= to_logic(wdata_taken);
    rin.rdata_count <= rdata_count_v;
    rin.rdata_owed <= rdata_owed_v;
    rin.acc_count <= acc_count_v;
    rin.acc_issue <= acc_issue_v;
    rin.close_valid <= close_valid_v;
    rin.close_bank <= close_bank_v;
    rin.refresh_due <= refresh_due_v;

    -- The ground for the cycle to come, out of the state the cycle to
    -- come will be in.
    rin.sched.bank <= head_bank_v;
    rin.sched.row <= head_row_v;
    rin.sched.column <= column_address(head_v);
    rin.sched.write <= head_write_v;
    rin.sched.valid <= to_logic(acc_count_g /= 0);
    rin.sched.blocked <= to_logic(wdata_left_v /= 0 or refresh_due_v = '1');
    rin.sched.active <= bank_active_v(head_bank_v);
    rin.sched.hit <= to_logic(bank_active_v(head_bank_v) = '1'
                              and bank_row_v(head_bank_v) = head_row_v);

    for b in 0 to bank_count_c - 1
    loop
      rin.sched.bank_sel(b) <= to_logic(b = head_bank_v);
      rin.sched.close_sel(b) <= to_logic(b = close_bank_v);
    end loop;

    rin.sched.activate_ok <= to_logic(
      may_activate(rp_ok_v(head_bank_v), rc_ok_v(head_bank_v),
                   since_any_activate_v));
    rin.sched.precharge_ok <= to_logic(
      may_precharge(head_bank_v, ras_ok_v(head_bank_v),
                    write_bank_v, read_bank_v,
                    since_write_v, since_read_command_v,
                    rdata_owed_v));
    rin.sched.write_ok <= to_logic(
      may_write(rcd_ok_v(head_bank_v), column_busy_v,
                wdata_count_g, rdata_owed_v));
    rin.sched.write_ok_arrived <= to_logic(
      may_write(rcd_ok_v(head_bank_v), column_busy_v,
                wdata_count_g + 1, rdata_owed_v));
    rin.sched.read_ok <= to_logic(
      may_read(rcd_ok_v(head_bank_v), column_busy_v, since_write_v,
               rdata_owed_v, rdata_count_g));
    rin.sched.close_ok <= to_logic(
      may_precharge(close_bank_v, ras_ok_v(close_bank_v),
                    write_bank_v, read_bank_v,
                    since_write_v, since_read_command_v,
                    rdata_owed_v));

    case r.state is
      when ST_RESET =>
        rin.step <= 0;
        rin.acc_fill <= 0;
        rin.acc_issue <= 0;
        rin.acc_count <= 0;
        rin.wdata_fill <= 0;
        rin.wdata_issue <= 0;
        rin.wdata_count <= 0;
        rin.wdata_left <= 0;
        rin.wdata_arrived <= '0';
        rin.rdata_fill <= 0;
        rin.rdata_drain <= 0;
        rin.rdata_count <= 0;
        rin.rdata_owed <= 0;
        rin.rddata_en_left <= 0;
        rin.column_busy <= 0;
        rin.bank_active <= (others => '0');
        rin.since_activate <= (others => age_saturated_c);
        rin.since_precharge <= (others => age_saturated_c);
        rin.since_any_activate <= age_saturated_c;
        rin.since_write <= age_saturated_c;
        rin.since_read_command <= age_saturated_c;
        rin.since_refresh <= age_saturated_c;
        rin.write_bank <= (others => '1');
        rin.read_bank <= (others => '1');
        rin.close_valid <= '0';
        rin.close_bank <= 0;
        rin.refresh_left <= to_unsigned(refi_c, refresh_width_c);
        rin.refresh_due <= '0';
        rin.sched.valid <= '0';
        rin.sched.blocked <= '1';
        rin.ready <= '0';
        rin.state <= ST_INIT_ISSUE;

      when ST_INIT_ISSUE =>
        rin.init_left <= to_unsigned(script_c.step(r.step).delay,
                                     init_width_c);
        rin.state <= ST_INIT_WAIT;

      when ST_INIT_WAIT =>
        if r.init_left = 0 then
          if r.step = step_max_c then
            rin.ready <= '1';
            rin.refresh_left <= to_unsigned(refi_c, refresh_width_c);
            rin.state <= ST_RUN;
          else
            rin.step <= r.step + 1;
            rin.state <= ST_INIT_ISSUE;
          end if;
        else
          rin.init_left <= r.init_left - 1;
        end if;

      when ST_RUN =>
        -- The data bus goes quiet before the refresh sequence takes
        -- over: a burst still putting its payload out keeps it.
        if r.refresh_due = '1' and r.wdata_left = 0 then
          rin.state <= ST_REFRESH_PRECHARGE;
        end if;

      when ST_REFRESH_PRECHARGE =>
        -- Waiting for the banks to become closeable takes as many
        -- cycles as the last access still owes, and the command that
        -- closes them is a single event: it belongs to the state
        -- entered once the wait is over, not to the wait.  Held here,
        -- it would reach the part while the write burst it has to
        -- follow is still on the bus, and the part would take it as
        -- the end of that burst.
        if all_closed then
          if precharge_settled then
            rin.state <= ST_REFRESH;
          end if;
        elsif refresh_ready then
          rin.state <= ST_REFRESH_PRECHARGE_ISSUE;
        end if;

      when ST_REFRESH_PRECHARGE_ISSUE =>
        rin.state <= ST_REFRESH_PRECHARGE;

      when ST_REFRESH =>
        if older_than(r.since_refresh, rfc_c) then
          rin.state <= ST_RUN;
        end if;
    end case;

    -- The refresh command itself is issued on the cycle the state is
    -- entered, so the stamp is cleared there.
    if r.state = ST_REFRESH_PRECHARGE and all_closed
      and precharge_settled then
      rin.since_refresh <= (others => '0');
    end if;
  end process;

  -- Outputs come out of the registers alone.  The pick is recomputed
  -- here rather than carried in a register of its own, which costs a
  -- priority chain over single bits and saves the cycle a registered
  -- command would cost.
  moore: process(r) is
    variable action_v: action_t;
    variable all_banks: unsigned(max_address_width_c - 1 downto 0);
    variable head_bank_v: unsigned(l_c.bank_width - 1 downto 0);
  begin
    dfi_o <= master_idle(dfi_config_c);
    cmd_o <= accept(r.ready = '1' and r.acc_count /= acc_depth_c);
    wdata_o <= accept(r.wdata_count /= wdata_depth_c);
    rdata_o <= rdata_idle;
    ready_o <= r.ready;

    action_v := next_action(r);

    all_banks := (others => '0');
    all_banks(10) := '1';

    head_bank_v := to_unsigned(r.sched.bank, l_c.bank_width);

    if r.rdata_count /= 0 then
      rdata_o <= rdata_beat(r.rdata(r.rdata_drain));
    end if;

    case r.state is
      when ST_RESET =>
        dfi_o <= master_reset(dfi_config_c);

      when ST_INIT_ISSUE =>
        dfi_o.command(0) <= command(dfi_config_c,
                                    script_c.step(r.step).command,
                                    bank => script_c.step(r.step).bank,
                                    address => script_c.step(r.step).address,
                                    cke => script_c.step(r.step).cke);
        dfi_o.reset_n <= script_c.step(r.step).reset_n;

      when ST_INIT_WAIT =>
        dfi_o.command(0) <= command(dfi_config_c, CMD_DESELECT,
                                    cke => script_c.step(r.step).cke);
        dfi_o.reset_n <= script_c.step(r.step).reset_n;

      when ST_REFRESH_PRECHARGE_ISSUE =>
        dfi_o.command(0) <= command(dfi_config_c, CMD_PRECHARGE,
                                    address => all_banks);

      when ST_REFRESH =>
        if r.since_refresh = 0 then
          dfi_o.command(0) <= command(dfi_config_c, CMD_REFRESH);
        end if;

      when ST_RUN =>
        case action_v is
          when ACT_CLOSE =>
            dfi_o.command(0)
              <= command(dfi_config_c, CMD_PRECHARGE,
                         bank => to_unsigned(r.close_bank, l_c.bank_width));

          when ACT_PRECHARGE =>
            dfi_o.command(0)
              <= command(dfi_config_c, CMD_PRECHARGE,
                         bank => head_bank_v);

          when ACT_ACTIVATE =>
            dfi_o.command(0)
              <= command(dfi_config_c, CMD_ACTIVATE,
                         bank => head_bank_v,
                         address => r.sched.row);

          when ACT_WRITE =>
            dfi_o.command(0)
              <= command(dfi_config_c, CMD_WRITE,
                         bank => head_bank_v,
                         address => r.sched.column);

          when ACT_READ =>
            dfi_o.command(0)
              <= command(dfi_config_c, CMD_READ,
                         bank => head_bank_v,
                         address => r.sched.column);

          when ACT_NONE =>
            null;
        end case;

      when others =>
        null;
    end case;

    -- Data goes out alongside the command; putting it CAS write
    -- latency later on the wire is the PHY's business.
    if action_v = ACT_WRITE or r.wdata_left /= 0 then
      dfi_o.wrdata <= to_data_vector(dfi_config_c,
                                     r.wdata(r.wdata_issue),
                                     r.wmask(r.wdata_issue));
      dfi_o.wrdata_en <= (others => '1');
    end if;

    -- The announcement spans the cycles its answer takes and drops
    -- between two reads, so a PHY that arms on the rising edge of
    -- rddata_en sees one edge per read.
    if action_v = ACT_READ or r.rddata_en_left /= 0 then
      dfi_o.rddata_en <= (others => '1');
    end if;
  end process;

end architecture;
