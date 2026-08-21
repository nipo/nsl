library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_inet;
use nsl_inet.switching.all;

entity switching_ingress is
  generic(
    config_c: config_t;
    port_index_c: port_index_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    flood_mask_i: in port_mask_t;

    in_i: in nsl_amba.axi4_stream.master_t;
    in_o: out nsl_amba.axi4_stream.slave_t;

    lookup_query_o: out lookup_query_t;
    lookup_result_i: in lookup_result_t;
    learn_o: out learn_t;

    frame_o: out nsl_amba.axi4_stream.master_t;
    frame_i: in nsl_amba.axi4_stream.slave_t;
    forward_o: out forward_req_t;
    forward_i: in forward_ack_t
    );
end entity;

library nsl_data, nsl_inet, nsl_logic, nsl_math, nsl_memory;
use nsl_data.bytestream.all;
use nsl_inet.ethernet.all;
use nsl_logic.bool.all;

architecture beh of switching_ingress is

  constant port_cfg_c: nsl_amba.axi4_stream.config_t := port_config(config_c);
  constant int_cfg_c: nsl_amba.axi4_stream.config_t := internal_config(config_c);

  -- Destination and source addresses, gathered in arrival order.
  constant hdr_cfg_c: nsl_amba.axi4_stream.buffer_config_t
    := nsl_amba.axi4_stream.buffer_config(port_cfg_c, 12);

  constant storage_width_c: natural := storage_width(config_c);
  constant buffer_word_l2_c: natural
    := config_c.buffer_bytes_l2 - nsl_math.arith.log2(config_c.byte_count);

  subtype address_t is unsigned(buffer_word_l2_c-1 downto 0);
  subtype word_count_t is unsigned(buffer_word_l2_c downto 0);
  subtype storage_word_t is std_ulogic_vector(storage_width_c-1 downto 0);

  constant buffer_word_count_c: natural := 2 ** buffer_word_l2_c;

  -- A frame is worth keeping from 14 bytes on. Expressed on the beat
  -- grid: that many complete beats, then that many bytes in the beat
  -- carrying the last byte.
  constant min_word_c: natural := 13 / config_c.byte_count;
  constant min_byte_c: natural := 14 - min_word_c * config_c.byte_count;

  -- One metadata entry per frame held in the buffer, sized for
  -- standard minimum-size Ethernet frames. Frames of 64 bytes and
  -- above can never fill the queue before they fill the buffer;
  -- shorter ones may, and then commit like a buffer overflow, that is,
  -- they get dropped as a whole.
  constant meta_depth_c: natural := buffer_word_count_c * config_c.byte_count / 64 + 1;
  -- Depth is rounded up to a power of two so that the queue's ring
  -- pointers are plain binary counters that wrap on their own.
  constant meta_word_count_c: natural := nsl_math.arith.align_up(meta_depth_c);

  constant meta_width_c: natural := config_c.port_count + word_count_t'length;
  subtype meta_word_t is std_ulogic_vector(meta_width_c-1 downto 0);

  constant no_port_c: port_mask_t := (others => '0');

  function self_mask return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    ret(port_index_c) := '1';
    return ret;
  end function;

  function enabled_ports return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    for i in 0 to config_c.port_count-1
    loop
      ret(i) := '1';
    end loop;
    return ret;
  end function;

  constant self_mask_c: port_mask_t := self_mask;
  constant enabled_ports_c: port_mask_t := enabled_ports;

  function meta_pack(mask: port_mask_t; words: word_count_t) return meta_word_t
  is
    variable ret: meta_word_t;
  begin
    for i in 0 to config_c.port_count-1
    loop
      ret(i) := mask(i);
    end loop;
    ret(meta_width_c-1 downto config_c.port_count) := std_ulogic_vector(words);
    return ret;
  end function;

  function meta_mask(v: meta_word_t) return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    for i in 0 to config_c.port_count-1
    loop
      ret(i) := v(i);
    end loop;
    return ret;
  end function;

  function meta_words(v: meta_word_t) return word_count_t
  is
    variable ret: word_count_t;
  begin
    ret := unsigned(v(meta_width_c-1 downto config_c.port_count));
    return ret;
  end function;

  -- Frame storage, written in reception order, read back once per
  -- destination port.
  signal ram_write_address_s: address_t;
  signal ram_write_en_s: std_ulogic;
  signal ram_write_data_s: storage_word_t;
  signal ram_read_address_s: address_t;
  signal ram_read_en_s: std_ulogic;
  signal ram_read_data_s: storage_word_t;

  signal meta_in_data_s, meta_out_data_s: meta_word_t;
  signal meta_in_valid_s: std_ulogic;
  signal meta_free_s: integer range 0 to meta_word_count_c;
  signal meta_out_valid_s, meta_out_ready_s: std_ulogic;

  -- Read side hands the words of a fully forwarded frame back to the
  -- write side.
  signal release_valid_s: std_ulogic;
  signal release_words_s: word_count_t;

begin

  -- Reception. Frames are written speculatively at the ring's write
  -- pointer and either committed, which publishes their metadata, or
  -- given up, which rewinds the write pointer to the frame start.
  wr_side: block is

    type state_t is (
      ST_RESET,
      -- Receiving a frame, storing it
      ST_FRAME,
      -- Frame is given up, swallow the remaining beats
      ST_DROP
      );

    -- Destination resolution of the frame being received.
    type lookup_t is (
      -- Egress mask not known yet
      LK_WAIT,
      -- Table query outstanding for this frame
      LK_QUERY,
      -- Egress mask resolved
      LK_DONE,
      -- Frame is given up, no mask needed
      LK_VOID
      );

    type query_t is (
      Q_IDLE,
      Q_RUNNING
      );

    -- Metadata entry waiting for a slot in the queue.
    type slot_t is
    record
      valid: std_ulogic;
      mask: port_mask_t;
      words: word_count_t;
    end record;

    type regs_t is
    record
      state: state_t;
      hdr: nsl_amba.axi4_stream.buffer_t;
      hdr_full: boolean;

      -- Next word to write, first word of the frame being received,
      -- and how many words it holds so far
      wptr: address_t;
      start: address_t;
      words: word_count_t;
      -- Words the ring can still take
      free: word_count_t;

      lk: lookup_t;
      mask: port_mask_t;

      q: query_t;
      q_mac: mac48_t;
      -- Frame owning the outstanding query has finished being received
      q_ended: boolean;
      -- ... and was committed
      q_good: boolean;
      -- ... holding that many words
      q_words: word_count_t;

      learn_valid: std_ulogic;
      learn_mac: mac48_t;

      -- Slot a holds the entry of a frame whose egress mask only
      -- arrived after it committed, slot b that of a frame which had
      -- its mask at commit time. A frame may only commit when both
      -- slots are free, which keeps a older than b, hence drained
      -- first. A full queue stops the slots from draining, so it
      -- reaches the commit decision through their occupancy alone,
      -- with no queue signal of its own in that decision.
      meta_a, meta_b: slot_t;

      -- Contract violations. They are latched rather than reported
      -- from the transition process because the ingress stream holds
      -- its beat for part of the cycle that follows the transfer,
      -- which would make a combinational report fire on stale inputs.
      err_late_lookup: boolean;
      err_stray_result: boolean;
      err_meta_full: boolean;
    end record;

    signal r, rin: regs_t;

    -- A beat is present on the ingress stream
    signal beat_s: std_ulogic;
    -- ... and it carries the last byte of its frame
    signal end_s: std_ulogic;
    -- ... and it goes to the storage ring
    signal write_s: std_ulogic;
    -- Frame is given up here, the write pointer rewinds
    signal doom_s: std_ulogic;
    -- Frame ends here and is worth keeping
    signal commit_s: std_ulogic;

    signal da_s, sa_s: mac48_t;
    -- Egress mask of the frame being received is known now, and its
    -- value
    signal fl_done_s: std_ulogic;
    signal fl_mask_s: port_mask_t;
    -- Table query for the frame being received is outstanding, or is
    -- being issued now
    signal fl_query_s: std_ulogic;
    -- Egress mask carried by the table answer of this cycle
    signal result_mask_s: port_mask_t;

    -- Wide comparisons the beat classification rests on, held one
    -- flip-flop away from it so that classifying a beat stays a
    -- shallow gate on stream bits and register outputs.
    --
    -- Ring has room for the beat being presented
    signal room_s: std_ulogic;
    -- Frame already holds more than, respectively exactly, the
    -- complete beats a 14-byte frame needs
    signal long_gt_s, long_eq_s: std_ulogic;
    -- Both metadata staging slots are free
    signal staged_s: std_ulogic;
    -- Metadata queue can take an entry. The count it reads is one
    -- cycle old and the push it commands reaches the queue one cycle
    -- after that, so two pushes may be under way and uncounted when
    -- it answers; at most one leaves the staging per cycle, so keeping
    -- two entries of the queue unused makes the answer safe.
    signal meta_room_s: std_ulogic;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        assert not rin.err_late_lookup
          report "Frame committed while its destination lookup could not even "
          &"be issued: MAC table answers slower than one frame"
          severity failure;
        assert not rin.err_stray_result
          report "MAC table answered a query the ingress does not expect"
          severity failure;
        assert not rin.err_meta_full
          report "Frame metadata staging overflow"
          severity failure;

        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
        r.hdr_full <= false;
        r.free <= to_unsigned(buffer_word_count_c, word_count_t'length);
        r.lk <= LK_WAIT;
        r.q <= Q_IDLE;
        r.q_ended <= false;
        r.q_good <= false;
        r.learn_valid <= '0';
        r.meta_a.valid <= '0';
        r.meta_b.valid <= '0';
        r.err_late_lookup <= false;
        r.err_stray_result <= false;
        r.err_meta_full <= false;
      end if;
    end process;

    -- room_s is deliberately one cycle old: a beat takes at most one
    -- word per cycle, so keeping the last word of the ring unused is
    -- enough to make the stale answer safe. The others are decoded on
    -- the way into their flip-flop, from the value the counter is
    -- about to take, and so carry no staleness at all.
    flags: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        room_s <= to_logic(r.free > 1);
        meta_room_s <= to_logic(meta_free_s > 2);
        long_gt_s <= to_logic(rin.words > min_word_c);
        long_eq_s <= to_logic(rin.words = min_word_c);
        staged_s <= to_logic(rin.meta_a.valid = '0'
                             and rin.meta_b.valid = '0');
      end if;

      if reset_n_i = '0' then
        room_s <= '1';
        meta_room_s <= '0';
        long_gt_s <= '0';
        long_eq_s <= '0';
        staged_s <= '1';
      end if;
    end process;

    -- Classification of the beat present on the ingress stream. This
    -- has to be visible outside the transition process because the
    -- storage write strobe and the write-side rewind both depend on
    -- it in the very cycle the beat is presented.
    decode: process(r, in_i, room_s, long_gt_s, long_eq_s, staged_s) is
      variable beat_v, last_v, bad_v, long_v: boolean;
    begin
      beat_v := r.state /= ST_RESET
                and nsl_amba.axi4_stream.is_valid(port_cfg_c, in_i);
      last_v := nsl_amba.axi4_stream.is_last(port_cfg_c, in_i);
      bad_v := nsl_amba.axi4_stream.user(port_cfg_c, in_i)(0) = '1';
      -- Beats are packed, so the beat carries at least min_byte_c
      -- bytes exactly when the byte at that offset is kept.
      long_v := long_gt_s = '1'
                or (long_eq_s = '1'
                    and nsl_amba.axi4_stream.keep(port_cfg_c,
                                                  in_i)(min_byte_c-1) = '1');

      beat_s <= to_logic(beat_v);
      end_s <= to_logic(beat_v and last_v);
      write_s <= to_logic(beat_v and r.state = ST_FRAME and room_s = '1');
      doom_s <= to_logic(beat_v and r.state = ST_FRAME
                         and (room_s = '0'
                              or (last_v
                                  and (bad_v
                                       or not long_v
                                       or staged_s = '0'))));
      commit_s <= to_logic(beat_v and r.state = ST_FRAME and room_s = '1'
                           and last_v and not bad_v and long_v
                           and staged_s = '1');
    end process;

    -- Destination resolution of the frame being received, as of this
    -- cycle. Both the lookup state machine and the commit path read
    -- it, and a frame short enough to end on the cycle its header
    -- completes needs the two to agree.
    resolve: process(r, flood_mask_i, lookup_result_i) is
      variable header_v: byte_string(0 to 11);
      variable flood_v: port_mask_t;
      variable result_v: port_mask_t;
    begin
      header_v := nsl_amba.axi4_stream.bytes(hdr_cfg_c, r.hdr);
      flood_v := flood_mask_i and not self_mask_c and enabled_ports_c;
      result_v := if_else(lookup_result_i.hit = '1',
                          lookup_result_i.mask, flood_mask_i)
                  and not self_mask_c and enabled_ports_c;

      da_s <= header_v(0 to 5);
      sa_s <= header_v(6 to 11);
      result_mask_s <= result_v;

      fl_done_s <= '0';
      fl_query_s <= '0';
      fl_mask_s <= r.mask;

      case r.lk is
        when LK_WAIT =>
          if r.hdr_full then
            if is_group(header_v(0 to 5)) then
              fl_done_s <= '1';
              fl_mask_s <= flood_v;
            elsif r.q = Q_IDLE then
              fl_query_s <= '1';
            end if;
          end if;

        when LK_QUERY =>
          if lookup_result_i.valid = '1' then
            fl_done_s <= '1';
            fl_mask_s <= result_v;
          else
            fl_query_s <= '1';
          end if;

        when LK_DONE =>
          fl_done_s <= '1';

        when LK_VOID =>
          null;
      end case;
    end process;

    transition: process(r, in_i, beat_s, end_s, write_s, doom_s, commit_s,
                        da_s, sa_s, fl_done_s, fl_query_s, fl_mask_s,
                        result_mask_s, lookup_result_i, meta_room_s,
                        release_valid_s, release_words_s) is
      variable freed_v: word_count_t;
      variable count_v: word_count_t;
    begin
      rin <= r;
      rin.learn_valid <= '0';
      rin.err_late_lookup <= false;
      rin.err_stray_result <= false;
      rin.err_meta_full <= false;

      freed_v := if_else(release_valid_s = '1', release_words_s,
                         word_count_t'(others => '0'));
      count_v := r.words + 1;

      -- Header capture. The buffer stops shifting once complete, so
      -- that both addresses stay readable until the frame ends.
      if beat_s = '1' and r.state = ST_FRAME and not r.hdr_full then
        rin.hdr <= nsl_amba.axi4_stream.shift(hdr_cfg_c, r.hdr, in_i);
        rin.hdr_full <= nsl_amba.axi4_stream.is_last(hdr_cfg_c, r.hdr);
      end if;

      -- Metadata staging hands one entry per cycle to the queue,
      -- oldest first.
      if meta_room_s = '1' then
        if r.meta_a.valid = '1' then
          rin.meta_a.valid <= '0';
        else
          rin.meta_b.valid <= '0';
        end if;
      end if;

      -- Table answer.
      if r.q = Q_RUNNING and lookup_result_i.valid = '1' then
        rin.q <= Q_IDLE;

        if r.q_ended then
          rin.q_ended <= false;
          rin.q_good <= false;

          if r.q_good then
            rin.meta_a.valid <= '1';
            rin.meta_a.mask <= result_mask_s;
            rin.meta_a.words <= r.q_words;

            if r.meta_a.valid = '1' and meta_room_s = '0' then
              rin.err_meta_full <= true;
            end if;
          end if;
        elsif r.lk /= LK_QUERY then
          rin.err_stray_result <= true;
        end if;
      end if;

      if doom_s = '0' then
        if fl_done_s = '1' then
          rin.mask <= fl_mask_s;
          rin.lk <= LK_DONE;
        elsif fl_query_s = '1' and r.lk = LK_WAIT then
          rin.q <= Q_RUNNING;
          rin.q_mac <= da_s;
          rin.q_ended <= false;
          rin.q_good <= false;
          rin.lk <= LK_QUERY;
        end if;
      end if;

      -- Ring pointers. A given-up frame takes its words back, a
      -- committed one leaves them to the read side until release.
      if doom_s = '1' then
        rin.wptr <= r.start;
        rin.words <= (others => '0');
        rin.free <= r.free + r.words + freed_v;
      elsif commit_s = '1' then
        rin.wptr <= r.wptr + 1;
        rin.start <= r.wptr + 1;
        rin.words <= (others => '0');
        rin.free <= r.free - 1 + freed_v;
      elsif write_s = '1' then
        rin.wptr <= r.wptr + 1;
        rin.words <= count_v;
        rin.free <= r.free - 1 + freed_v;
      else
        rin.free <= r.free + freed_v;
      end if;

      if commit_s = '1' then
        rin.learn_valid <= to_logic(not is_group(sa_s));
        rin.learn_mac <= sa_s;

        if fl_done_s = '1' then
          rin.meta_b.valid <= '1';
          rin.meta_b.mask <= fl_mask_s;
          rin.meta_b.words <= count_v;
        elsif fl_query_s = '1' then
          rin.q_ended <= true;
          rin.q_good <= true;
          rin.q_words <= count_v;
        else
          rin.err_late_lookup <= true;
        end if;
      end if;

      if doom_s = '1' then
        if fl_query_s = '1' and r.lk = LK_QUERY then
          rin.q_ended <= true;
          rin.q_good <= false;
        end if;

        rin.lk <= LK_VOID;

        if end_s = '0' then
          rin.state <= ST_DROP;
        end if;
      end if;

      if end_s = '1' then
        rin.state <= ST_FRAME;
        rin.hdr <= nsl_amba.axi4_stream.reset(hdr_cfg_c);
        rin.hdr_full <= false;
        rin.lk <= LK_WAIT;
      end if;

      if r.state = ST_RESET then
        rin.state <= ST_FRAME;
        rin.hdr <= nsl_amba.axi4_stream.reset(hdr_cfg_c);
        rin.hdr_full <= false;
        rin.wptr <= (others => '0');
        rin.start <= (others => '0');
        rin.words <= (others => '0');
      end if;
    end process;

    outputs: process(r) is
    begin
      lookup_query_o.valid <= to_logic(r.q = Q_RUNNING);
      lookup_query_o.mac <= r.q_mac;

      learn_o.valid <= r.learn_valid;
      learn_o.mac <= r.learn_mac;
    end process;

    -- Queue write command, a pipeline stage of its own so that the
    -- staging drain decision does not reach the queue's memory write
    -- port. It latches the entry on the very edge that frees the slot
    -- it came from, which is what keeps the two in step.
    push: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        meta_in_valid_s <= (r.meta_a.valid or r.meta_b.valid) and meta_room_s;

        if r.meta_a.valid = '1' then
          meta_in_data_s <= meta_pack(r.meta_a.mask, r.meta_a.words);
        else
          meta_in_data_s <= meta_pack(r.meta_b.mask, r.meta_b.words);
        end if;
      end if;

      if reset_n_i = '0' then
        meta_in_valid_s <= '0';
      end if;
    end process;

    ram_write_address_s <= r.wptr;
    ram_write_en_s <= write_s;
    ram_write_data_s <= storage_pack(config_c, in_i);

    in_o <= nsl_amba.axi4_stream.accept(port_cfg_c, r.state /= ST_RESET);

  end block;

  -- Forwarding. The head frame is announced to the fabric with its
  -- pending mask and its words are streamed once per destination
  -- port. Address generation makes a replay a plain counter reload,
  -- and a frame with no destination is stepped over without reading a
  -- single word.
  rd_side: block is

    type state_t is (
      ST_RESET,
      ST_IDLE,
      -- Egress mask is empty, frame is released without being read
      ST_SKIP,
      ST_STREAM,
      ST_WAIT_ACK,
      ST_REWIND,
      ST_RELEASE
      );

    type regs_t is
    record
      state: state_t;
      mask: port_mask_t;

      -- First word of the head frame and its length
      head: address_t;
      words: word_count_t;

      -- Next word to ask the streamer for, and how many are left in
      -- the copy under way
      addr: address_t;
      to_fetch: word_count_t;
    end record;

    signal r, rin: regs_t;

    signal addr_valid_s, addr_ready_s: std_ulogic;
    signal addr_s: address_t;
    signal data_valid_s, data_ready_s: std_ulogic;
    signal data_s: storage_word_t;
    -- Marks the last word of a copy along the streamer pipeline
    signal last_in_s, last_out_s: std_ulogic_vector(0 downto 0);

    -- A frame is offered to the fabric, and its words are on their
    -- way out. Both decode the state the machine is about to enter,
    -- so they carry the value a decode of the current state would,
    -- one flip-flop closer to the port.
    signal announce_s: std_ulogic;
    signal streaming_s: std_ulogic;

    -- Output slice. The streamer tells its fill level with a
    -- comparator, so its data valid is arithmetic rather than a
    -- flip-flop; the slice ends that cone here and hands the fabric a
    -- beat that is entirely register-held.
    signal beat_s, out_beat_s: nsl_amba.axi4_stream.master_t;
    signal slice_in_slave_s: nsl_amba.axi4_stream.slave_t;
    signal slice_in_ready_s: std_ulogic;
    signal slice_out_valid_s: std_ulogic;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        -- A copy hands its last word to the slice only once every
        -- address of the frame has been issued, so the address
        -- counter and the streamer are empty from the moment the copy
        -- stops being streamed.
        assert not (r.state = ST_WAIT_ACK
                    or r.state = ST_REWIND
                    or r.state = ST_RELEASE)
          or (r.to_fetch = 0 and data_valid_s = '0')
          report "Frame copy ended with words still to fetch"
          severity failure;

        -- The slice may still be handing the tail of the copy to the
        -- fabric while the acknowledge is awaited. The fabric only
        -- acknowledges once it has taken the last beat out of it, so
        -- by the time the next copy is set up the slice is empty.
        -- Were it not so, beats of the copy that just ended would
        -- lead the next one.
        assert not (r.state = ST_REWIND or r.state = ST_RELEASE)
          or slice_out_valid_s = '0'
          report "Frame copy left beats behind in the output slice"
          severity failure;

        -- Streaming stops one slice stage before the fabric sees the
        -- end of the copy, so an acknowledge can never land while the
        -- copy is still being streamed.
        assert r.state /= ST_STREAM
          or (forward_i.taken and enabled_ports_c) = no_port_c
          report "Fabric acknowledged a copy it cannot have taken yet"
          severity failure;

        -- The word the address counter calls the last of the frame is
        -- the word the write side marked as such. A metadata length
        -- that has drifted from the stored frame shows up here.
        assert data_valid_s = '0'
          or last_out_s(0)
             = to_logic(nsl_amba.axi4_stream.is_last(int_cfg_c, beat_s))
          report "Frame length in the metadata does not match the stored frame"
          severity failure;

        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
        r.mask <= no_port_c;
        r.to_fetch <= (others => '0');
      end if;
    end process;

    -- Everything the fabric sees leaves this block from a flip-flop
    -- with no state decoding behind it: forward_o.valid from
    -- announce_s, forward_o.mask from r.mask, and the frame stream
    -- from the output slice.
    ports: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        announce_s <= to_logic(rin.state = ST_STREAM
                               or rin.state = ST_WAIT_ACK
                               or rin.state = ST_REWIND);
        streaming_s <= to_logic(rin.state = ST_STREAM);
      end if;

      if reset_n_i = '0' then
        announce_s <= '0';
        streaming_s <= '0';
      end if;
    end process;

    -- A copy stops being streamed where its last word enters the
    -- slice. The fabric's own view of the end of the copy is one or
    -- more cycles later, at the far side of the slice, and that is
    -- still where it acknowledges from; waiting for the acknowledge
    -- covers the difference, and nothing the fabric drives reaches
    -- this decision.
    transition: process(r, meta_out_valid_s, meta_out_data_s, addr_ready_s,
                        data_valid_s, last_out_s, slice_in_ready_s,
                        forward_i) is
      variable taken_v: port_mask_t;
      variable left_v: port_mask_t;
      variable meta_mask_v: port_mask_t;
      variable meta_words_v: word_count_t;
      variable fetch_v: boolean;
      variable done_v: boolean;
    begin
      rin <= r;

      taken_v := forward_i.taken and enabled_ports_c;
      left_v := r.mask and not (forward_i.taken and enabled_ports_c);
      meta_mask_v := meta_mask(meta_out_data_s);
      meta_words_v := meta_words(meta_out_data_s);
      fetch_v := r.state = ST_STREAM and r.to_fetch /= 0
                 and addr_ready_s = '1';
      done_v := r.state = ST_STREAM
                and data_valid_s = '1'
                and last_out_s(0) = '1'
                and slice_in_ready_s = '1';

      if fetch_v then
        rin.addr <= r.addr + 1;
        rin.to_fetch <= r.to_fetch - 1;
      end if;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.head <= (others => '0');

        when ST_IDLE =>
          if meta_out_valid_s = '1' then
            rin.mask <= meta_mask_v;
            rin.words <= meta_words_v;
            rin.addr <= r.head;
            rin.to_fetch <= meta_words_v;

            if meta_mask_v = no_port_c then
              rin.state <= ST_SKIP;
            else
              rin.state <= ST_STREAM;
            end if;
          end if;

        when ST_SKIP | ST_RELEASE =>
          rin.head <= r.head + r.words(address_t'range);
          rin.state <= ST_IDLE;

        when ST_STREAM =>
          if done_v then
            rin.state <= ST_WAIT_ACK;
          end if;

        when ST_WAIT_ACK =>
          if taken_v /= no_port_c then
            rin.mask <= left_v;

            if left_v = no_port_c then
              rin.state <= ST_RELEASE;
            else
              rin.state <= ST_REWIND;
            end if;
          end if;

        when ST_REWIND =>
          rin.addr <= r.head;
          rin.to_fetch <= r.words;
          rin.state <= ST_STREAM;
      end case;
    end process;

    outputs: process(r, data_valid_s, data_s, streaming_s, announce_s,
                     slice_in_ready_s) is
    begin
      -- Streamer word on its way into the slice. Sanitizing it is what
      -- keeps the decode's integer conversion away from the
      -- metavalues the streamer holds before its first read.
      beat_s <= storage_unpack(config_c,
                               std_ulogic_vector(to_01(unsigned(data_s), '0')));
      beat_s.valid <= data_valid_s and streaming_s;

      forward_o.valid <= announce_s;
      forward_o.mask <= r.mask;

      meta_out_ready_s <= to_logic(r.state = ST_IDLE);

      addr_valid_s <= to_logic(r.state = ST_STREAM and r.to_fetch /= 0);
      addr_s <= r.addr;
      last_in_s(0) <= to_logic(r.to_fetch = 1);
      data_ready_s <= streaming_s and slice_in_ready_s;

      release_valid_s <= to_logic(r.state = ST_SKIP or r.state = ST_RELEASE);
      release_words_s <= r.words;
    end process;

    output_slice: nsl_amba.stream_fifo.axi4_stream_slice
      generic map(
        config_c => int_cfg_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => beat_s,
        in_o => slice_in_slave_s,

        out_o => out_beat_s,
        out_i => frame_i
        );

    slice_in_ready_s <= to_logic(nsl_amba.axi4_stream.is_ready(int_cfg_c,
                                                               slice_in_slave_s));
    slice_out_valid_s <= to_logic(nsl_amba.axi4_stream.is_valid(int_cfg_c,
                                                                out_beat_s));

    frame_o <= out_beat_s;

    -- Addresses are only fed for the words of the copy under way, so
    -- the streamer is drained by the time a copy ends: a rewind or a
    -- skip cannot leak a prefetched word into the next copy. That
    -- holds whatever the memory latency is, the address count per
    -- copy being what governs it.
    reader: nsl_memory.streamer.memory_streamer
      generic map(
        addr_width_c => buffer_word_l2_c,
        data_width_c => storage_width_c,
        memory_latency_c => 2,
        sideband_width_c => 1
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        addr_valid_i => addr_valid_s,
        addr_ready_o => addr_ready_s,
        addr_i => addr_s,
        sideband_i => last_in_s,

        data_valid_o => data_valid_s,
        data_ready_i => data_ready_s,
        data_o => data_s,
        sideband_o => last_out_s,

        mem_enable_o => ram_read_en_s,
        mem_address_o => ram_read_address_s,
        mem_sideband_o => open,
        mem_data_i => ram_read_data_s
        );

  end block;

  -- Frame storage. The output register keeps the block RAM's
  -- clock-to-out in a stage of its own, which is what the streamer's
  -- memory_latency_c accounts for.
  storage: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => buffer_word_l2_c,
      data_size_c => storage_width_c,
      registered_output_c => true
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => ram_write_address_s,
      write_en_i => ram_write_en_s,
      write_data_i => ram_write_data_s,

      read_address_i => ram_read_address_s,
      read_en_i => ram_read_en_s,
      read_data_o => ram_read_data_s
      );

  -- Metadata queue: one entry per frame held in the storage ring,
  -- written in commit order and taken one entry per frame by the
  -- forwarding side. A ring of its own rather than a general-purpose
  -- fifo: one entry leaves it per frame, so spending two cycles to
  -- refill its output register costs nothing, and in exchange the
  -- pointer logic is an increment and a compare.
  meta_queue: block is

    constant depth_l2_c: natural := nsl_math.arith.log2(meta_word_count_c);
    subtype ptr_t is unsigned(depth_l2_c-1 downto 0);

    type regs_t is
    record
      -- Next entry to write, and next to hand out
      wptr, rptr: ptr_t;
      -- Entries the ring can still take
      free: natural range 0 to meta_word_count_c;
      -- A read is on its way out of the memory
      fetching: std_ulogic;
      -- Entry sitting at the output
      out_valid: std_ulogic;
      out_data: meta_word_t;

      err_full: boolean;
    end record;

    signal r, rin: regs_t;

    signal fetch_s: std_ulogic;
    signal ram_data_s: meta_word_t;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        assert not rin.err_full
          report "Frame metadata queue overflow"
          severity failure;

        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.wptr <= (others => '0');
        r.rptr <= (others => '0');
        r.free <= meta_word_count_c;
        r.fetching <= '0';
        r.out_valid <= '0';
        r.err_full <= false;
      end if;
    end process;

    transition: process(r, meta_in_valid_s, meta_out_ready_s, ram_data_s) is
      variable push_v, fetch_v: boolean;
    begin
      rin <= r;
      rin.err_full <= false;

      push_v := meta_in_valid_s = '1';
      -- One read at a time, started as soon as the output is, or is
      -- about to become, empty.
      fetch_v := r.fetching = '0'
                 and (r.out_valid = '0' or meta_out_ready_s = '1')
                 and r.free /= meta_word_count_c;

      if push_v then
        rin.wptr <= r.wptr + 1;
        rin.err_full <= r.free = 0;
      end if;

      if fetch_v then
        rin.rptr <= r.rptr + 1;
      end if;

      -- The guard only keeps the counter in range long enough for the
      -- overflow report above to come out; a push on a full ring is
      -- an error, not a case to handle.
      if push_v and not fetch_v and r.free /= 0 then
        rin.free <= r.free - 1;
      elsif fetch_v and not push_v then
        rin.free <= r.free + 1;
      end if;

      rin.fetching <= to_logic(fetch_v);
      fetch_s <= to_logic(fetch_v);

      if r.out_valid = '1' and meta_out_ready_s = '1' then
        rin.out_valid <= '0';
      end if;

      if r.fetching = '1' then
        rin.out_data <= ram_data_s;
        rin.out_valid <= '1';
      end if;
    end process;

    meta_out_data_s <= r.out_data;
    meta_out_valid_s <= r.out_valid;
    meta_free_s <= r.free;

    ram: nsl_memory.ram.ram_2p_r_w
      generic map(
        addr_size_c => depth_l2_c,
        data_size_c => meta_width_c
        )
      port map(
        clock_i(0) => clock_i,

        write_address_i => r.wptr,
        write_en_i => meta_in_valid_s,
        write_data_i => meta_in_data_s,

        read_address_i => r.rptr,
        read_en_i => fetch_s,
        read_data_o => ram_data_s
        );

  end block;

end architecture;
