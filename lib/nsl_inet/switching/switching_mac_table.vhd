library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_inet, nsl_logic, nsl_math, nsl_memory;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_inet.ethernet.all;
use nsl_inet.switching.all;
use nsl_logic.bool.all;

entity switching_mac_table is
  generic(
    config_c: config_t;
    static_macs_c: mac48_vector := no_static_macs_c;
    static_ports_c: port_index_vector := no_static_ports_c
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    query_i: in lookup_query_vector(0 to config_c.port_count-1);
    result_o: out lookup_result_vector(0 to config_c.port_count-1);

    learn_i: in learn_vector(0 to config_c.port_count-1)
    );
end entity;

-- One address table shared by every port, served by a single lookup
-- engine.
--
-- Learning mode stores entries in a set-associative table: the address
-- is hashed to a bucket, the bucket holds config_c.table_way_count
-- ways, and each way lives in its own two-port memory (one read port,
-- one write port) so that a whole bucket is read in one cycle. Static
-- mode replaces the memories by a constant vector of entries holding a
-- single bucket, which turns the very same compare stage into an exact
-- parallel compare over the static list.
--
-- Pipeline, one register per stage, at most one task per stage:
--
--   boundary: query_i and learn_i are captured per port. Nothing
--             downstream reads the ports combinationally.
--   sel:      round-robin arbitration over the captured requests picks
--             one task. Priority is aging sweep, then learn, then
--             query.
--   fetch:    the address of the selected task is muxed out of the
--             per-port capture registers.
--   addr:     the bucket index, hashed from the fetched address, is
--             presented to the memory read ports.
--   data:     memory read in flight. The memories run with a
--             registered output, so their data lands a second cycle
--             later and the compare stage starts from a flop instead
--             of from a block RAM combinational output.
--   cmp:      the bucket contents are compared against the task
--             address. This stage owns the wide compare and nothing
--             else: the per-way match, free and stale bits, the port
--             mask of every way and the sweep rewrite of every way all
--             go into registers.
--   dec:      way selection, answer and write word, all built from the
--             registers the compare stage filled. Nothing here depends
--             on a memory output any more.
--   write:    the answer is pulsed on result_o and the memory write
--             ports are driven, both straight out of registers.
--
-- A learn writes word_pack('1', '1', task port, task address), which
-- depends on nothing but the task registers, so the write word is
-- wired straight from the dec stage into the write register with no
-- way selection in front of it. Only the sweep needs a word built from
-- what the memories returned, and it gets that one stage earlier, in
-- the compare stage, where it is a pure rewiring of the read word.
-- Both writes are then issued from the same dec stage, so there is a
-- single write point and a single hazard rule.
--
-- Read-after-write hazard rule: a bucket read presented while a
-- write-back for that bucket is still in the pipeline returns
-- pre-write contents, and the memories give no guarantee at all for a
-- read presented on the very cycle of a write. Rather than compare
-- bucket indices, the issue stage simply never presents a read while a
-- write-back is anywhere between the addr stage and the memory. That
-- takes four cycles (addr, data, cmp, dec, then the write register
-- drives the memory), so a writing task occupies five consecutive addr
-- slots: its own, then four bubbles. The stall is a countdown loaded
-- when a writing task enters the addr stage rather than a decode of
-- the stages it occupies, which keeps the pipeline task types off the
-- arbitration and bookkeeping paths. The post-reset invalidation sweep
-- owns the write registers outright and keeps arbitration idle for the
-- same reason.
--
-- Latency, from the cycle query_i.valid is asserted to the cycle
-- result_o.valid pulses, is 8 cycles plus the arbitration wait. Each
-- query queued ahead costs one cycle, each learn or sweep task queued
-- ahead costs five. For P ports the worst case is therefore
--
--   8 + (P-1) + 5*(learns ahead) + 5*(sweep visits during the wait)
--
-- A minimum-size frame is 16 beats at 4 bytes per beat, which is the
-- budget the requester would like the answer to fit in. Queries alone
-- fit that up to P=9. One learn or one sweep visit ahead brings the
-- bound down to P=4. Under a burst where every port commits a frame on
-- the cycle every port also queries, 8+(P-1)+5P leaves no useful port
-- count at all. Those last cases are throughput statements, not
-- correctness ones: switching_ingress accepts a lookup result arriving
-- after the end of its frame and merely defers the forwarding
-- announcement, so an over-budget answer delays one frame instead of
-- breaking it. Should the bursty case ever need to fit, the bubble can
-- be made conditional on the entering task's bucket matching one of
-- the write-backs in flight; that trades a bucket comparator in the
-- hash stage for the idle slots.
architecture beh of switching_mac_table is

  -- Static mode holds the whole list in a single bucket, so both modes
  -- share the bucket/way addressing below.
  constant bucket_l2_c: natural
    := if_else(config_c.learning_enabled, config_c.table_entry_count_l2, 0);
  constant bucket_count_c: natural := 2 ** bucket_l2_c;
  constant way_count_c: natural
    := if_else(config_c.learning_enabled,
               config_c.table_way_count,
               nsl_math.arith.max(1, static_macs_c'length));

  -- A one-bucket table still needs an address bit: numeric_std has no
  -- meaningful conversion for a null address vector.
  constant ram_addr_size_c: natural := nsl_math.arith.max(1, bucket_l2_c);

  -- Cycles the issue stage stays idle behind a task that writes back,
  -- one per stage the write-back still has to walk plus the cycle the
  -- write register drives the memory.
  constant wb_hold_c: natural := 4;

  constant aging_enabled_c: boolean
    := config_c.learning_enabled and config_c.age_time_l2 /= 0;
  -- Cycles between two aging visits, so that a full sweep of the
  -- table takes about 2**age_time_l2 cycles.
  constant scrub_shift_c: natural
    := if_else(config_c.age_time_l2 > bucket_l2_c,
               config_c.age_time_l2 - bucket_l2_c,
               0);
  constant scrub_period_c: natural := 2 ** nsl_math.arith.min(30, scrub_shift_c);

  constant port_width_c: natural := nsl_math.arith.log2(max_port_count_c);
  constant valid_bit_c: natural := 0;
  constant fresh_bit_c: natural := 1;
  constant port_lsb_c: natural := 2;
  constant mac_lsb_c: natural := port_lsb_c + port_width_c;
  constant entry_width_c: natural := mac_lsb_c + 48;

  subtype entry_word_t is std_ulogic_vector(entry_width_c-1 downto 0);
  type entry_word_vector is array(natural range <>) of entry_word_t;
  type port_mask_vector is array(natural range <>) of port_mask_t;
  subtype way_set_t is std_ulogic_vector(0 to way_count_c-1);

  function word_valid(w: entry_word_t) return std_ulogic
  is
  begin
    return w(valid_bit_c);
  end function;

  -- Cleared by the aging sweep, set again by any learn on the entry.
  -- An entry found stale by the sweep is invalidated.
  function word_fresh(w: entry_word_t) return std_ulogic
  is
  begin
    return w(fresh_bit_c);
  end function;

  -- Sanitized: a bucket that has not been through the post-reset
  -- invalidation sweep yet still reaches the decode.
  function word_port(w: entry_word_t) return port_index_t
  is
  begin
    return to_integer(to_01(unsigned(w(mac_lsb_c-1 downto port_lsb_c)), '0'));
  end function;

  function word_mac(w: entry_word_t) return mac48_t
  is
    variable ret: mac48_t;
  begin
    for i in 0 to 5
    loop
      ret(i) := w(mac_lsb_c + i*8 + 7 downto mac_lsb_c + i*8);
    end loop;
    return ret;
  end function;

  function word_pack(valid, fresh: std_ulogic;
                     port_index: port_index_t;
                     mac: mac48_t) return entry_word_t
  is
    variable ret: entry_word_t;
  begin
    ret(valid_bit_c) := valid;
    ret(fresh_bit_c) := fresh;
    ret(mac_lsb_c-1 downto port_lsb_c)
      := std_ulogic_vector(to_unsigned(port_index, port_width_c));
    for i in 0 to 5
    loop
      ret(mac_lsb_c + i*8 + 7 downto mac_lsb_c + i*8) := mac(i);
    end loop;
    return ret;
  end function;

  constant no_mac_c: mac48_t := (others => x"00");
  constant invalid_word_c: entry_word_t := word_pack('0', '0', 0, no_mac_c);

  function static_table return entry_word_vector
  is
    variable ret: entry_word_vector(0 to way_count_c-1) := (others => invalid_word_c);
  begin
    -- In learning mode the static list is unused but this constant
    -- still elaborates, and the list may then be longer than the
    -- bucket.
    if not config_c.learning_enabled then
      for i in 0 to static_macs_c'length-1
      loop
        ret(i) := word_pack('1', '1',
                            static_ports_c(static_ports_c'low + i),
                            static_macs_c(static_macs_c'low + i));
      end loop;
    end if;
    return ret;
  end function;

  constant static_words_c: entry_word_vector(0 to way_count_c-1) := static_table;

  -- Evaluated at elaboration so that no process carries these checks
  -- into synthesis.
  function config_check return boolean
  is
  begin
    assert static_macs_c'length = static_ports_c'length
      report "Static MAC and port lists must have the same length"
      severity failure;

    assert config_c.learning_enabled or static_macs_c'length /= 0
      report "A static MAC table with no entry never hits"
      severity warning;

    assert bucket_l2_c <= 16
      report "MAC table hash only yields 16 bucket index bits"
      severity failure;

    assert not aging_enabled_c or scrub_period_c >= 16
      report "config_c.age_time_l2 must exceed table_entry_count_l2 by at least 4,"
      &" otherwise the aging sweep starves lookups"
      severity failure;

    for i in 0 to static_macs_c'length-1
    loop
      assert static_ports_c(static_ports_c'low + i) < config_c.port_count
        report "Static MAC table entry points at a port out of range"
        severity failure;
      assert not is_group(static_macs_c(static_macs_c'low + i))
        report "Static MAC table entry holds a group address"
        severity warning;
    end loop;

    return true;
  end function;

  constant config_ok_c: boolean := config_check;

  -- CRC-16-CCITT over the six address bytes. A CRC of a fixed-length
  -- message is an affine map of the address bits, so addresses that
  -- only differ in their low bits, as a range of consecutive station
  -- addresses inside one OUI does, spread evenly over the buckets.
  constant hash_params_c: crc_params_t := crc_params(
    init => x"ffff",
    poly => x"11021",
    complement_state => false,
    complement_input => false,
    byte_bit_order => BIT_ORDER_DESCENDING,
    spill_order => EXP_ORDER_DESCENDING,
    byte_order => BYTE_ORDER_INCREASING
    );

  function bucket_of(mac: mac48_t) return natural
  is
    constant state_c: crc_state_t
      := crc_update(hash_params_c, crc_init(hash_params_c), mac);
    constant spill_c: std_ulogic_vector := crc_spill_vector(hash_params_c, state_c);
    alias xspill_c: std_ulogic_vector(spill_c'length-1 downto 0) is spill_c;
  begin
    if bucket_l2_c = 0 then
      return 0;
    end if;
    return to_integer(unsigned(xspill_c(bucket_l2_c-1 downto 0)));
  end function;

  function any_set(v: std_ulogic_vector) return boolean
  is
  begin
    for i in v'range
    loop
      if v(i) = '1' then
        return true;
      end if;
    end loop;
    return false;
  end function;

  -- Lowest asserted bit, as a one-hot vector, all zeroes if no bit is
  -- asserted.
  function first_oh(v: std_ulogic_vector) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to v'length-1) := (others => '0');
  begin
    for i in 0 to v'length-1
    loop
      if v(v'low + i) = '1' then
        ret(i) := '1';
        return ret;
      end if;
    end loop;
    return ret;
  end function;

  -- First asserted bit at or after start, wrapping around, as a
  -- one-hot vector.
  function rr_first_oh(v: std_ulogic_vector; start: natural)
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to v'length-1) := (others => '0');
    variable index_v: natural;
  begin
    for i in 0 to v'length-1
    loop
      index_v := (start + i) mod v'length;
      if v(v'low + index_v) = '1' then
        ret(index_v) := '1';
        return ret;
      end if;
    end loop;
    return ret;
  end function;

  -- Same, as an index. 0 if no bit is asserted.
  function rr_first(v: std_ulogic_vector; start: natural) return natural
  is
    variable index_v: natural;
  begin
    for i in 0 to v'length-1
    loop
      index_v := (start + i) mod v'length;
      if v(v'low + index_v) = '1' then
        return index_v;
      end if;
    end loop;
    return 0;
  end function;

  function one_hot(index: port_index_t) return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    ret(index) := '1';
    return ret;
  end function;

  -- Or of the masks the one-hot selector points at.
  function mask_select(masks: port_mask_vector;
                       sel: std_ulogic_vector) return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    for i in 0 to sel'length-1
    loop
      if sel(sel'low + i) = '1' then
        ret := ret or masks(masks'low + i);
      end if;
    end loop;
    return ret;
  end function;

  subtype way_index_t is natural range 0 to way_count_c-1;
  subtype bucket_index_t is natural range 0 to bucket_count_c-1;
  subtype local_port_t is natural range 0 to config_c.port_count-1;
  subtype port_set_t is std_ulogic_vector(0 to config_c.port_count-1);
  subtype mac_set_t is mac48_vector(0 to config_c.port_count-1);

  constant no_port_c: port_set_t := (others => '0');
  constant no_way_c: way_set_t := (others => '0');

  function way_one_hot(index: way_index_t) return way_set_t
  is
    variable ret: way_set_t := (others => '0');
  begin
    ret(index) := '1';
    return ret;
  end function;

  type task_t is (
    TASK_NONE,
    TASK_QUERY,
    TASK_LEARN,
    TASK_SCRUB
    );

  function writes(t: task_t) return boolean
  is
  begin
    return t = TASK_LEARN or t = TASK_SCRUB;
  end function;

  -- Travels down the pipeline with the task. bucket carries the sweep
  -- target from arbitration, then the hash for every task from the
  -- addr stage on. The requesting port is carried both encoded, for
  -- the entry word a learn writes, and one-hot, so that the answer and
  -- the per-port bookkeeping never decode an index.
  type task_ctx_t is
  record
    task: task_t;
    port_index: local_port_t;
    port_oh: port_set_t;
    mac: mac48_t;
    bucket: bucket_index_t;
  end record;

  constant idle_ctx_c: task_ctx_t := (
    task => TASK_NONE,
    port_index => 0,
    port_oh => no_port_c,
    mac => no_mac_c,
    bucket => 0
    );

  type regs_t is
  record
    -- Query interface capture. answered marks a port whose result has
    -- been pulsed but whose request has not gone low yet.
    q_valid: port_set_t;
    q_mac: mac_set_t;
    busy: port_set_t;
    answered: port_set_t;
    query_rr: local_port_t;

    -- Learn interface capture, one holding register per port.
    lp_valid: port_set_t;
    lp_mac: mac_set_t;
    learn_rr: local_port_t;

    -- Post-reset sweep invalidating every bucket.
    init_pending: boolean;
    init_bucket: bucket_index_t;

    scrub_pending: boolean;
    scrub_bucket: bucket_index_t;
    scrub_timer: natural range 0 to scrub_period_c-1;

    -- Way to evict when a bucket holds neither the address nor a
    -- reusable way.
    victim: way_index_t;

    sel: task_ctx_t;
    fetch: task_ctx_t;
    addr: task_ctx_t;
    data: task_ctx_t;
    cmp: task_ctx_t;
    dec: task_ctx_t;

    -- Cycles left before the write-back in flight reaches the
    -- memories. Non-zero keeps the issue stage idle.
    wb_hold: natural range 0 to wb_hold_c;

    -- Compare stage results.
    d_match_oh: way_set_t;
    d_free_oh: way_set_t;
    d_stale_oh: way_set_t;
    d_hit: std_ulogic;
    d_free_any: boolean;
    d_stale_any: boolean;
    d_way_mask: port_mask_vector(0 to way_count_c-1);
    d_sweep_en: way_set_t;
    d_sweep_word: entry_word_vector(0 to way_count_c-1);

    -- Memory write ports, driven with no logic in front of them.
    wb_en: way_set_t;
    wb_bucket: bucket_index_t;
    wb_data: entry_word_vector(0 to way_count_c-1);

    result_oh: port_set_t;
    result_hit: std_ulogic;
    result_mask: port_mask_t;
  end record;

  signal r, rin: regs_t;

  constant read_en_c: std_ulogic := '1';

  signal read_data_s, scrub_word_s: entry_word_vector(0 to way_count_c-1);
  signal read_bucket_s, write_bucket_s: unsigned(ram_addr_size_c-1 downto 0);

  -- Bucket decode, in the compare stage.
  signal way_valid_s, way_match_s, way_free_s, way_stale_s: way_set_t;
  signal way_mask_s: port_mask_vector(0 to way_count_c-1);

  -- Way selection and answer, in the dec stage.
  signal target_oh_s: way_set_t;
  signal hit_mask_s: port_mask_t;
  signal learn_word_s: entry_word_t;

  -- Arbitration decode.
  signal query_req_s: port_set_t;
  signal query_oh_s, learn_oh_s: port_set_t;
  signal query_any_s, learn_any_s: boolean;
  signal query_port_s, learn_port_s: local_port_t;
  signal issue_query_oh_s, issue_learn_oh_s: port_set_t;
  signal capture_oh_s, busy_clear_s: port_set_t;

  signal sel_mac_s: mac48_t;
  signal fetch_bucket_s: bucket_index_t;

begin

  learning_storage: if config_c.learning_enabled generate
    ways: for w in 0 to way_count_c-1 generate
      -- Registered output: read data lands two cycles after the
      -- address, and the read enable must therefore stay asserted for
      -- the whole memory read pipeline to advance.
      ram: nsl_memory.ram.ram_2p_r_w
        generic map(
          addr_size_c => ram_addr_size_c,
          data_size_c => entry_width_c,
          clock_count_c => 1,
          registered_output_c => true
          )
        port map(
          clock_i(0) => clock_i,
          write_address_i => write_bucket_s,
          write_en_i => r.wb_en(w),
          write_data_i => r.wb_data(w),
          read_address_i => read_bucket_s,
          read_en_i => read_en_c,
          read_data_o => read_data_s(w)
          );
    end generate;

    read_bucket_s <= to_unsigned(r.addr.bucket, ram_addr_size_c);
    write_bucket_s <= to_unsigned(r.wb_bucket, ram_addr_size_c);
  end generate;

  static_storage: if not config_c.learning_enabled generate
    ways: for w in 0 to way_count_c-1 generate
      read_data_s(w) <= static_words_c(w);
    end generate;
  end generate;

  -- Compare stage. The address compare is the only deep thing here;
  -- the port mask and the sweep rewrite of a way are rewirings of the
  -- read word and run beside it.
  bucket_decode: for w in 0 to way_count_c-1 generate
    way_valid_s(w) <= word_valid(read_data_s(w));
    way_match_s(w) <= way_valid_s(w)
                      and to_logic(word_mac(read_data_s(w)) = r.cmp.mac);
    way_free_s(w) <= not way_valid_s(w);
    way_stale_s(w) <= way_valid_s(w) and not word_fresh(read_data_s(w));
    way_mask_s(w) <= one_hot(word_port(read_data_s(w)));

    -- Freshness demotion, then invalidation on the next visit.
    scrub_word_s(w) <= word_pack(word_fresh(read_data_s(w)), '0',
                                 word_port(read_data_s(w)),
                                 word_mac(read_data_s(w)));
  end generate;

  -- Dec stage, entirely off the memory outputs.
  --
  -- Write target: refresh in place, else take a free way, else the way
  -- the aging sweep is about to reclaim, else the round-robin victim.
  target_oh_s <= r.d_match_oh when r.d_hit = '1'
                 else r.d_free_oh when r.d_free_any
                 else r.d_stale_oh when r.d_stale_any
                 else way_one_hot(r.victim);

  hit_mask_s <= mask_select(r.d_way_mask, r.d_match_oh);

  learn_word_s <= word_pack('1', '1', r.dec.port_index, r.dec.mac);

  -- Arbitration decode.
  query_req_s <= r.q_valid and not r.busy;
  query_any_s <= any_set(query_req_s);
  query_oh_s <= rr_first_oh(query_req_s, r.query_rr);
  query_port_s <= rr_first(query_req_s, r.query_rr);
  learn_any_s <= any_set(r.lp_valid);
  learn_oh_s <= rr_first_oh(r.lp_valid, r.learn_rr);
  learn_port_s <= rr_first(r.lp_valid, r.learn_rr);

  -- The issue condition is spelled out of r.wb_hold rather than out of
  -- a shared stall signal: the transition process needs the same test
  -- and a signal would reach it one delta late.
  issue_learn_oh_s <= learn_oh_s
                      when r.wb_hold = 0 and not r.init_pending
                           and not r.scrub_pending
                      else no_port_c;
  issue_query_oh_s <= query_oh_s
                      when r.wb_hold = 0 and not r.init_pending
                           and not r.scrub_pending and not learn_any_s
                      else no_port_c;

  learn_capture: for p in 0 to config_c.port_count-1 generate
    capture_oh_s(p) <= learn_i(p).valid
                       and to_logic(config_c.learning_enabled)
                       and to_logic(not is_group(learn_i(p).mac));
  end generate;

  busy_clear_s <= r.answered and not r.q_valid;

  sel_mac_s <= r.lp_mac(r.sel.port_index) when r.sel.task = TASK_LEARN
               else r.q_mac(r.sel.port_index);

  fetch_bucket_s <= r.fetch.bucket when r.fetch.task = TASK_SCRUB
                    else bucket_of(r.fetch.mac);

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.q_valid <= (others => '0');
      r.busy <= (others => '0');
      r.answered <= (others => '0');
      r.query_rr <= 0;
      r.lp_valid <= (others => '0');
      r.learn_rr <= 0;
      r.init_pending <= config_c.learning_enabled;
      r.init_bucket <= 0;
      r.scrub_pending <= false;
      r.scrub_bucket <= 0;
      r.scrub_timer <= scrub_period_c-1;
      r.victim <= 0;
      r.sel <= idle_ctx_c;
      r.fetch <= idle_ctx_c;
      r.addr <= idle_ctx_c;
      r.data <= idle_ctx_c;
      r.cmp <= idle_ctx_c;
      r.dec <= idle_ctx_c;
      r.wb_hold <= 0;
      r.wb_en <= (others => '0');
      r.result_oh <= (others => '0');
    end if;
  end process;

  transition: process(r, query_i, learn_i, sel_mac_s, fetch_bucket_s,
                      query_any_s, query_port_s, query_oh_s, learn_any_s,
                      learn_port_s, learn_oh_s, issue_query_oh_s,
                      issue_learn_oh_s, capture_oh_s, busy_clear_s,
                      way_valid_s, way_match_s, way_free_s, way_stale_s,
                      way_mask_s, scrub_word_s, target_oh_s, hit_mask_s,
                      learn_word_s) is
  begin
    rin <= r;

    -- Query interface capture. The address register holds its value
    -- while the request is low, so the fetch stage still finds it
    -- there whatever the requester does after arbitration.
    for p in 0 to config_c.port_count-1
    loop
      rin.q_valid(p) <= query_i(p).valid;
      if query_i(p).valid = '1' then
        rin.q_mac(p) <= query_i(p).mac;
      end if;
    end loop;

    -- Learn interface capture, one holding register per port. Capture
    -- outranks the issue clear, so a strobe landing on the port being
    -- issued is kept rather than lost, and a port that strobes twice
    -- before being served keeps the newer address.
    rin.lp_valid <= (r.lp_valid and not issue_learn_oh_s) or capture_oh_s;
    for p in 0 to config_c.port_count-1
    loop
      if capture_oh_s(p) = '1' then
        rin.lp_mac(p) <= learn_i(p).mac;
      end if;
    end loop;

    -- A port stays busy until its answer has been pulsed and its
    -- request has been seen low again, so a request held for one more
    -- cycle, as the requester does while it samples the result, is
    -- never served twice. Issue and clear cannot hit the same port on
    -- the same cycle: one needs the request high, the other low.
    rin.busy <= (r.busy and not busy_clear_s) or issue_query_oh_s;
    rin.answered <= (r.answered and not busy_clear_s) or r.result_oh;

    -- Compare stage. Nothing but the address compare depth lands in
    -- these registers.
    rin.d_match_oh <= first_oh(way_match_s);
    rin.d_hit <= to_logic(any_set(way_match_s));
    rin.d_free_oh <= first_oh(way_free_s);
    rin.d_free_any <= any_set(way_free_s);
    rin.d_stale_oh <= first_oh(way_stale_s);
    rin.d_stale_any <= any_set(way_stale_s);
    rin.d_sweep_en <= way_valid_s;
    for w in 0 to way_count_c-1
    loop
      rin.d_way_mask(w) <= way_mask_s(w);
      rin.d_sweep_word(w) <= scrub_word_s(w);
    end loop;

    -- Dec stage
    rin.result_oh <= (others => '0');
    rin.wb_en <= (others => '0');

    if r.dec.task = TASK_QUERY then
      rin.result_oh <= r.dec.port_oh;

      -- A group address is never a valid source address, so it is
      -- never in the table. Answering a miss keeps that true even for
      -- a table holding a bogus static entry.
      if r.d_hit = '1' and not is_group(r.dec.mac) then
        rin.result_hit <= '1';
        rin.result_mask <= hit_mask_s;
      else
        rin.result_hit <= '0';
        rin.result_mask <= (others => '0');
      end if;
    end if;

    if r.dec.task = TASK_LEARN then
      rin.wb_bucket <= r.dec.bucket;
      rin.wb_en <= target_oh_s;
      for w in 0 to way_count_c-1
      loop
        rin.wb_data(w) <= learn_word_s;
      end loop;

      -- Advanced on every learn rather than on evictions only: the
      -- bucket decode does not tell whether the way it picked was
      -- taken by an eviction, and a free-running pointer spreads
      -- evictions over the ways just as well.
      rin.victim <= (r.victim + 1) mod way_count_c;
    end if;

    if r.dec.task = TASK_SCRUB then
      rin.wb_bucket <= r.dec.bucket;
      rin.wb_en <= r.d_sweep_en;
      for w in 0 to way_count_c-1
      loop
        rin.wb_data(w) <= r.d_sweep_word(w);
      end loop;
    end if;

    -- Issue stages. The memory read pipeline always advances; the
    -- three stages ahead of it freeze while a write-back is on its way
    -- to the memories.
    rin.data <= r.addr;
    rin.cmp <= r.data;
    rin.dec <= r.cmp;

    rin.wb_hold <= 0;

    if r.wb_hold /= 0 then
      rin.addr <= idle_ctx_c;
      rin.wb_hold <= r.wb_hold - 1;
    else
      rin.addr <= task_ctx_t'(task => r.fetch.task,
                              port_index => r.fetch.port_index,
                              port_oh => r.fetch.port_oh,
                              mac => r.fetch.mac,
                              bucket => fetch_bucket_s);
      rin.fetch <= task_ctx_t'(task => r.sel.task,
                               port_index => r.sel.port_index,
                               port_oh => r.sel.port_oh,
                               mac => sel_mac_s,
                               bucket => r.sel.bucket);
      rin.sel <= idle_ctx_c;

      if writes(r.fetch.task) then
        rin.wb_hold <= wb_hold_c;
      end if;

      if not r.init_pending then
        if r.scrub_pending then
          rin.sel <= task_ctx_t'(task => TASK_SCRUB,
                                 port_index => 0,
                                 port_oh => no_port_c,
                                 mac => no_mac_c,
                                 bucket => r.scrub_bucket);
          rin.scrub_pending <= false;
          if r.scrub_bucket = bucket_count_c-1 then
            rin.scrub_bucket <= 0;
          else
            rin.scrub_bucket <= r.scrub_bucket + 1;
          end if;
        elsif learn_any_s then
          rin.sel <= task_ctx_t'(task => TASK_LEARN,
                                 port_index => learn_port_s,
                                 port_oh => learn_oh_s,
                                 mac => no_mac_c,
                                 bucket => 0);
          rin.learn_rr <= (learn_port_s + 1) mod config_c.port_count;
        elsif query_any_s then
          rin.sel <= task_ctx_t'(task => TASK_QUERY,
                                 port_index => query_port_s,
                                 port_oh => query_oh_s,
                                 mac => no_mac_c,
                                 bucket => 0);
          rin.query_rr <= (query_port_s + 1) mod config_c.port_count;
        end if;
      end if;
    end if;

    -- Aging sweep pacing, after the issue stage so that a visit
    -- falling due on the cycle the previous one is issued is not
    -- dropped.
    if aging_enabled_c then
      if r.scrub_timer = 0 then
        rin.scrub_timer <= scrub_period_c-1;
        rin.scrub_pending <= true;
      else
        rin.scrub_timer <= r.scrub_timer - 1;
      end if;
    end if;

    -- Post-reset invalidation sweep. It borrows the same write
    -- registers, one bucket per cycle, and keeps arbitration idle
    -- until it is over.
    if r.init_pending then
      rin.wb_bucket <= r.init_bucket;
      rin.wb_en <= (others => '1');
      for w in 0 to way_count_c-1
      loop
        rin.wb_data(w) <= invalid_word_c;
      end loop;

      if r.init_bucket = bucket_count_c-1 then
        rin.init_pending <= false;
        rin.init_bucket <= 0;
      else
        rin.init_bucket <= r.init_bucket + 1;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    for p in 0 to config_c.port_count-1
    loop
      if r.result_oh(p) = '1' then
        result_o(p) <= lookup_result_t'(valid => '1',
                                        hit => r.result_hit,
                                        mask => r.result_mask);
      else
        result_o(p) <= lookup_result_t'(valid => '0',
                                        hit => '0',
                                        mask => (others => '0'));
      end if;
    end loop;
  end process;

end architecture;
