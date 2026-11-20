library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_memory, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.ncm.all;

entity ncm_receiver is
  generic(
    ntb_config_c : config_t;
    frame_config_c : config_t;
    ntb_max_size_c : positive := 16384;
    datagram_max_size_c : positive := 1514
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ntb_i : in master_t;
    ntb_o : out slave_t;

    frame_o : out master_t;
    frame_i : in slave_t;

    stats_o : out ncm_receiver_stats_t
    );
end entity;

-- Two stages around a two-buffer RAM of 16-bit words:
--
-- * the loader takes the NTB stream a beat at a time, checks the NTH16
--   header and stores the rest of the block, byte-wise (byte write
--   enables), in the buffer it owns, then hands the buffer over;
--
-- * the emitter walks the NDP16 chain of a full buffer: it reads the
--   NDP and entry fields, then the datagram words, and pushes the bytes
--   belonging to the datagram into a small byte queue, from which
--   frame beats are built. Reads take two cycles (address register,
--   RAM), tracked by a two-entry tag pipeline; a credit on the queue
--   keeps the reads in flight from overflowing it.
--
-- Frames follow the nsl_inet.stream conventions: at a 4-byte width each
-- one starts with the front pad of nsl_inet.stream_mac (zeros, so the
-- payload after the ethernet header lands on a beat boundary), and the
-- reject flag is driven low on the last beat: there is no FCS to check,
-- bad datagram entries are skipped instead.
architecture beh of ncm_receiver is

  constant ntb_width_c : natural := ntb_config_c.data_width;
  constant frame_width_c : natural := frame_config_c.data_width;
  constant word_addr_size_c : natural := nsl_math.arith.log2(ntb_max_size_c / 2);
  constant addr_size_c : natural := word_addr_size_c + 1;
  constant word_count_c : natural := 2 ** word_addr_size_c;
  constant queue_depth_c : natural := 8;
  constant ethernet_header_size_c : natural := 14;
  -- nsl_inet.stream_mac.ethernet_frame_offset() of the frame stream
  constant front_pad_c : natural
    := (frame_width_c - ethernet_header_size_c mod frame_width_c) mod frame_width_c;
  -- Reject flag, cleared (user_width 0: null, not driven)
  constant user_ok_c : std_ulogic_vector(frame_config_c.user_width-1 downto 0)
    := (others => '0');
  -- Smallest block: NTH16 and an NDP16 with one entry and its terminator.
  constant ntb_min_size_c : natural := ncm_nth16_length_c + 16;

  subtype offset_t is natural range 0 to 65535;
  type offset_vector is array(natural range <>) of offset_t;
  subtype word_index_t is natural range 0 to word_count_c-1;

  type load_state_t is (
    LOAD_HEADER,
    LOAD_BODY
    );

  type emit_state_t is (
    EMIT_IDLE,
    EMIT_NDP,         -- read the 4 NDP16 header fields
    EMIT_NDP_WAIT,
    EMIT_NDP_CHECK,
    EMIT_ENTRY,       -- read one datagram entry (index, length)
    EMIT_ENTRY_WAIT,
    EMIT_ENTRY_CHECK,
    EMIT_PAD,         -- front pad of a frame (4-byte frame stream)
    EMIT_DATA,        -- read the datagram words
    EMIT_DONE         -- next NDP of the chain, or release the buffer
    );

  type tag_kind_t is (
    TAG_NONE,
    TAG_NDP,
    TAG_ENTRY,
    TAG_DATA
    );

  type tag_t is
  record
    kind : tag_kind_t;
    field : natural range 0 to 3;
    -- data: bytes of the word belonging to the datagram, last one
    lo, hi, last : boolean;
  end record;
  constant tag_none_c : tag_t := (TAG_NONE, 0, false, false, false);
  type tag_vector is array(natural range <>) of tag_t;

  type queue_t is array(0 to queue_depth_c-1) of byte;

  type regs_t is
  record
    -- Loader
    load_state : load_state_t;
    load_buffer : natural range 0 to 1;
    header : byte_string(0 to ncm_nth16_length_c-1);
    header_count : natural range 0 to ncm_nth16_length_c;
    load_offset : offset_t;
    load_left : offset_t;
    in_sync : boolean;
    write_en : std_ulogic_vector(1 downto 0);
    write_address : unsigned(addr_size_c-1 downto 0);
    write_data : byte_string(0 to 1);

    -- Buffers
    full : std_ulogic_vector(0 to 1);
    block_length : offset_vector(0 to 1);
    ndp_index : offset_vector(0 to 1);

    -- Emitter
    emit_state : emit_state_t;
    emit_buffer : natural range 0 to 1;
    length : offset_t;
    ndp : offset_t;
    ndp_ok : boolean;
    ndp_length : offset_t;
    ndp_next : offset_t;
    hops : natural range 0 to 3;
    field : natural range 0 to 3;
    entry_word : natural range 0 to word_count_c + 1;  -- steps past the table at its end
    entries_left : natural range 0 to 16383;
    entry_index : offset_t;
    entry_length : offset_t;
    data_word : word_index_t;
    data_end_word : word_index_t;
    data_first : offset_t;
    data_last : offset_t;
    read_address : unsigned(addr_size_c-1 downto 0);
    tag : tag_vector(0 to 1);

    -- Byte queue towards frame_o
    queue : queue_t;
    queue_last : std_ulogic_vector(0 to queue_depth_c-1);
    queue_read : natural range 0 to queue_depth_c-1;
    queue_count : natural range 0 to queue_depth_c;

    stats : ncm_receiver_stats_t;
  end record;

  signal r, rin : regs_t;
  signal read_data_s : std_ulogic_vector(15 downto 0);

  function le16(b : byte_string) return offset_t
  is
    alias bb : byte_string(0 to 1) is b;
  begin
    return to_integer(unsigned(bb(1)) & unsigned(bb(0)));
  end function;

  -- Bytes of the next frame beat: a whole beat, or the bytes up to the
  -- end of a datagram; 0 while the queue cannot form one.
  function frame_beat_size(r : regs_t) return natural
  is
  begin
    for i in 0 to frame_width_c-1
    loop
      if i >= r.queue_count then
        return 0;
      elsif r.queue_last((r.queue_read + i) mod queue_depth_c) = '1' then
        return i + 1;
      end if;
    end loop;
    return frame_width_c;
  end function;

  function word_address(buf : natural; word : natural) return unsigned
  is
  begin
    return to_unsigned(buf, 1) & to_unsigned(word, word_addr_size_c);
  end function;

  function zero_stats return ncm_receiver_stats_t
  is
  begin
    return (others => (others => '0'));
  end function;

begin

  assert ntb_width_c = 1 or ntb_width_c = 2
    report "NTB stream must be 1 or 2 bytes wide"
    severity failure;
  assert frame_width_c = 1 or frame_width_c = 2 or frame_width_c = 4
    report "Frame stream must be 1, 2 or 4 bytes wide"
    severity failure;
  assert frame_config_c.has_last
    report "Frame stream must have a last signal"
    severity failure;
  assert frame_width_c = 1 or frame_config_c.has_keep
    report "A frame stream wider than a byte must have keep"
    severity failure;
  assert ntb_max_size_c = 2 * word_count_c and ntb_max_size_c <= 65536
    report "ntb_max_size_c must be a power of two, at most 65536"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.load_state <= LOAD_HEADER;
      r.load_buffer <= 0;
      r.header_count <= 0;
      r.in_sync <= true;
      r.write_en <= "00";
      r.full <= "00";
      r.emit_state <= EMIT_IDLE;
      r.emit_buffer <= 0;
      r.tag <= (others => tag_none_c);
      r.queue_read <= 0;
      r.queue_count <= 0;
      r.stats <= zero_stats;
    end if;
  end process;

  transition: process(r, ntb_i, frame_i, read_data_s) is
    variable full_v : std_ulogic_vector(0 to 1);
    variable stats_v : ncm_receiver_stats_t;
    -- loader
    variable state_v : load_state_t;
    variable buffer_v : natural range 0 to 1;
    variable header_v : byte_string(0 to ncm_nth16_length_c-1);
    variable count_v : natural range 0 to ncm_nth16_length_c;
    variable offset_v, left_v : offset_t;
    variable in_sync_v, beat_done_v : boolean;
    variable in_bytes_v : byte_string(0 to ntb_width_c-1);
    variable in_count_v : natural range 0 to ntb_width_c;
    variable header_length_v, block_length_v, ndp_v : offset_t;
    -- emitter
    variable word_v : byte_string(0 to 1);
    variable got_ndp_v, got_entry_v : boolean;
    variable issue_v : tag_t;
    variable issue_word_v : word_index_t;
    variable inflight_v : natural range 0 to 2;
    -- queue
    variable queue_v : queue_t;
    variable queue_last_v : std_ulogic_vector(0 to queue_depth_c-1);
    variable queue_read_v : natural range 0 to queue_depth_c-1;
    variable queue_count_v : natural range 0 to queue_depth_c;
    variable pop_v : natural range 0 to frame_width_c;

    procedure header_error is
    begin
      if in_sync_v then
        stats_v.header_error_count := stats_v.header_error_count + 1;
        in_sync_v := false;
      end if;
    end procedure;

    procedure push(b : byte; last : boolean) is
      variable pos : natural range 0 to queue_depth_c-1;
    begin
      pos := (queue_read_v + queue_count_v) mod queue_depth_c;
      queue_v(pos) := b;
      if last then
        queue_last_v(pos) := '1';
      else
        queue_last_v(pos) := '0';
      end if;
      queue_count_v := queue_count_v + 1;
    end procedure;
  begin
    rin <= r;

    full_v := r.full;
    stats_v := r.stats;
    queue_v := r.queue;
    queue_last_v := r.queue_last;
    queue_read_v := r.queue_read;
    queue_count_v := r.queue_count;

    -- Frame beat taken by the consumer
    pop_v := frame_beat_size(r);
    if pop_v /= 0 and is_ready(frame_config_c, frame_i) then
      queue_read_v := (queue_read_v + pop_v) mod queue_depth_c;
      queue_count_v := queue_count_v - pop_v;
    end if;

    ----------------------------------------------------------------- loader
    rin.write_en <= "00";
    rin.write_address <= (others => '-');
    rin.write_data <= (others => dontcare_byte_c);

    state_v := r.load_state;
    buffer_v := r.load_buffer;
    header_v := r.header;
    count_v := r.header_count;
    offset_v := r.load_offset;
    left_v := r.load_left;
    in_sync_v := r.in_sync;

    if is_valid(ntb_config_c, ntb_i) and r.full(r.load_buffer) = '0' then
      in_bytes_v := bytes(ntb_config_c, ntb_i);
      in_count_v := byte_count(ntb_config_c, ntb_i);
      beat_done_v := false;

      for j in 0 to ntb_width_c-1
      loop
        if j < in_count_v and not beat_done_v then
          case state_v is
            when LOAD_HEADER =>
              if count_v < 4 and in_bytes_v(j) /= ncm_nth16_signature_c(count_v) then
                -- Not a header: a block may only start on a beat
                -- boundary, so only this beat's first byte can start
                -- the next attempt.
                header_error;
                if j = 0 and in_bytes_v(0) = ncm_nth16_signature_c(0) then
                  header_v(0) := in_bytes_v(0);
                  count_v := 1;
                else
                  count_v := 0;
                  beat_done_v := true;
                end if;
              else
                header_v(count_v) := in_bytes_v(j);
                count_v := count_v + 1;
              end if;

              if count_v = ncm_nth16_length_c then
                count_v := 0;
                beat_done_v := true;
                header_length_v := le16(header_v(4 to 5));
                block_length_v := le16(header_v(8 to 9));
                ndp_v := le16(header_v(10 to 11));
                if header_length_v = ncm_nth16_length_c
                  and block_length_v >= ntb_min_size_c
                  and block_length_v <= ntb_max_size_c
                  and ndp_v >= ncm_nth16_length_c
                  and ndp_v mod 2 = 0
                  and ndp_v + 16 <= block_length_v then
                  rin.block_length(buffer_v) <= block_length_v;
                  rin.ndp_index(buffer_v) <= ndp_v;
                  offset_v := ncm_nth16_length_c;
                  left_v := block_length_v - ncm_nth16_length_c;
                  state_v := LOAD_BODY;
                else
                  header_error;
                end if;
              end if;

            when LOAD_BODY =>
              -- Body bytes of one beat fall in one RAM word: blocks start
              -- on beat boundaries and the header is a whole number of
              -- words.
              rin.write_address <= word_address(buffer_v, offset_v / 2);
              rin.write_en(offset_v mod 2) <= '1';
              rin.write_data(offset_v mod 2) <= in_bytes_v(j);
              offset_v := offset_v + 1;
              left_v := left_v - 1;
              if left_v = 0 then
                full_v(buffer_v) := '1';
                buffer_v := 1 - buffer_v;
                in_sync_v := true;
                stats_v.ntb_count := stats_v.ntb_count + 1;
                state_v := LOAD_HEADER;
                beat_done_v := true;
              end if;
          end case;
        end if;
      end loop;
    end if;

    rin.load_state <= state_v;
    rin.load_buffer <= buffer_v;
    rin.header <= header_v;
    rin.header_count <= count_v;
    rin.load_offset <= offset_v;
    rin.load_left <= left_v;
    rin.in_sync <= in_sync_v;

    ---------------------------------------------------------- read results
    word_v := (0 => read_data_s(7 downto 0), 1 => read_data_s(15 downto 8));
    got_ndp_v := false;
    got_entry_v := false;

    case r.tag(1).kind is
      when TAG_NDP =>
        case r.tag(1).field is
          when 0 => rin.ndp_ok <= word_v = ncm_ndp16_signature_c(0 to 1);
          when 1 => rin.ndp_ok <= r.ndp_ok and word_v = ncm_ndp16_signature_c(2 to 3);
          when 2 => rin.ndp_length <= le16(word_v);
          when 3 => rin.ndp_next <= le16(word_v); got_ndp_v := true;
        end case;

      when TAG_ENTRY =>
        if r.tag(1).field = 0 then
          rin.entry_index <= le16(word_v);
        else
          rin.entry_length <= le16(word_v);
          got_entry_v := true;
        end if;

      when TAG_DATA =>
        if r.tag(1).lo then
          push(word_v(0), r.tag(1).last and not r.tag(1).hi);
        end if;
        if r.tag(1).hi then
          push(word_v(1), r.tag(1).last);
        end if;

      when TAG_NONE =>
        null;
    end case;

    ----------------------------------------------------------------- emitter
    -- Read results land in registers (above), so each wait state hands
    -- over to a check state that sees them.
    issue_v := tag_none_c;
    issue_word_v := 0;
    inflight_v := 0;
    if r.tag(0).kind = TAG_DATA then
      inflight_v := 2;
    end if;

    case r.emit_state is
      when EMIT_IDLE =>
        if full_v(r.emit_buffer) = '1' then
          rin.length <= r.block_length(r.emit_buffer);
          rin.ndp <= r.ndp_index(r.emit_buffer);
          rin.hops <= 0;
          rin.field <= 0;
          rin.emit_state <= EMIT_NDP;
        end if;

      when EMIT_NDP =>
        issue_v := (TAG_NDP, r.field, false, false, false);
        issue_word_v := r.ndp / 2 + r.field;
        if r.field = 3 then
          rin.emit_state <= EMIT_NDP_WAIT;
        else
          rin.field <= r.field + 1;
        end if;

      when EMIT_NDP_WAIT =>
        if got_ndp_v then
          rin.emit_state <= EMIT_NDP_CHECK;
        end if;

      when EMIT_NDP_CHECK =>
        if r.ndp_ok and r.ndp_length >= 16
          and r.ndp + r.ndp_length <= r.length then
          rin.entry_word <= r.ndp / 2 + 4;
          rin.entries_left <= (r.ndp_length - 8) / 4;
          rin.field <= 0;
          rin.emit_state <= EMIT_ENTRY;
        else
          stats_v.ndp_error_count := stats_v.ndp_error_count + 1;
          rin.ndp_next <= 0;
          rin.emit_state <= EMIT_DONE;
        end if;

      when EMIT_ENTRY =>
        if r.entries_left = 0 then
          rin.emit_state <= EMIT_DONE;
        else
          issue_v := (TAG_ENTRY, r.field, false, false, false);
          issue_word_v := r.entry_word + r.field;
          if r.field = 1 then
            rin.emit_state <= EMIT_ENTRY_WAIT;
          else
            rin.field <= 1;
          end if;
        end if;

      when EMIT_ENTRY_WAIT =>
        if got_entry_v then
          rin.emit_state <= EMIT_ENTRY_CHECK;
        end if;

      when EMIT_ENTRY_CHECK =>
        rin.entry_word <= r.entry_word + 2;
        rin.entries_left <= r.entries_left - 1;
        rin.field <= 0;
        if r.entry_index = 0 or r.entry_length = 0 then
          rin.emit_state <= EMIT_DONE;      -- end of the datagram table
        elsif r.entry_index >= ncm_nth16_length_c
          and r.entry_length >= ethernet_header_size_c
          and r.entry_length <= datagram_max_size_c
          and r.entry_index + r.entry_length <= r.length then
          rin.data_word <= r.entry_index / 2;
          rin.data_end_word <= (r.entry_index + r.entry_length - 1) / 2;
          rin.data_first <= r.entry_index;
          rin.data_last <= r.entry_index + r.entry_length - 1;
          stats_v.datagram_count := stats_v.datagram_count + 1;
          if front_pad_c /= 0 then
            rin.emit_state <= EMIT_PAD;
          else
            rin.emit_state <= EMIT_DATA;
          end if;
        else
          stats_v.datagram_error_count := stats_v.datagram_error_count + 1;
          rin.emit_state <= EMIT_ENTRY;
        end if;

      when EMIT_PAD =>
        -- No data read in flight: the previous datagram ended at least
        -- two entry reads ago.
        if queue_count_v + front_pad_c <= queue_depth_c then
          for i in 1 to front_pad_c
          loop
            push(x"00", false);
          end loop;
          rin.emit_state <= EMIT_DATA;
        end if;

      when EMIT_DATA =>
        if queue_count_v + inflight_v + 2 <= queue_depth_c then
          issue_v := (TAG_DATA, 0,
                      2 * r.data_word >= r.data_first,
                      2 * r.data_word + 1 <= r.data_last,
                      r.data_word = r.data_end_word);
          issue_word_v := r.data_word;
          if r.data_word = r.data_end_word then
            rin.emit_state <= EMIT_ENTRY;
          else
            rin.data_word <= r.data_word + 1;
          end if;
        end if;

      when EMIT_DONE =>
        -- Reads of this buffer still in flight complete first.
        if r.tag(0).kind = TAG_NONE and r.tag(1).kind = TAG_NONE then
          if r.ndp_next /= 0 and r.hops < 3
            and r.ndp_next >= ncm_nth16_length_c
            and r.ndp_next mod 2 = 0
            and r.ndp_next + 16 <= r.length then
            rin.ndp <= r.ndp_next;
            rin.hops <= r.hops + 1;
            rin.field <= 0;
            rin.emit_state <= EMIT_NDP;
          else
            full_v(r.emit_buffer) := '0';
            rin.emit_buffer <= 1 - r.emit_buffer;
            rin.emit_state <= EMIT_IDLE;
          end if;
        end if;
    end case;

    rin.read_address <= word_address(r.emit_buffer, issue_word_v);
    rin.tag(0) <= issue_v;
    rin.tag(1) <= r.tag(0);

    rin.full <= full_v;
    rin.stats <= stats_v;
    rin.queue <= queue_v;
    rin.queue_last <= queue_last_v;
    rin.queue_read <= queue_read_v;
    rin.queue_count <= queue_count_v;
  end process;

  moore: process(r) is
    variable size_v : natural range 0 to frame_width_c;
    variable user_v : std_ulogic_vector(frame_config_c.user_width-1 downto 0);
    variable bytes_v : byte_string(0 to frame_width_c-1);
    variable keep_v : std_ulogic_vector(0 to frame_width_c-1);
    variable last_v : boolean;
  begin
    ntb_o <= accept(ntb_config_c, r.full(r.load_buffer) = '0');
    stats_o <= r.stats;

    size_v := frame_beat_size(r);
    bytes_v := (others => dontcare_byte_c);
    keep_v := (others => '0');
    last_v := false;
    for i in 0 to frame_width_c-1
    loop
      if i < size_v then
        bytes_v(i) := r.queue((r.queue_read + i) mod queue_depth_c);
        keep_v(i) := '1';
        last_v := r.queue_last((r.queue_read + i) mod queue_depth_c) = '1';
      end if;
    end loop;

    if size_v = 0 then
      frame_o <= transfer(frame_config_c,
                          bytes => bytes_v,
                          valid => false);
    else
      user_v := (others => '-');
      if last_v then
        user_v := user_ok_c;
      end if;
      frame_o <= transfer(frame_config_c,
                          bytes => bytes_v,
                          keep => keep_v,
                          user => user_v,
                          valid => true,
                          last => last_v);
    end if;
  end process;

  storage: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => addr_size_c,
      word_size_c => 8,
      data_word_count_c => 2,
      registered_output_c => false,
      b_can_write_c => false
      )
    port map(
      a_clock_i => clock_i,
      a_write_en_i => r.write_en,
      a_address_i => r.write_address,
      a_data_i(15 downto 8) => r.write_data(1),
      a_data_i(7 downto 0) => r.write_data(0),

      b_clock_i => clock_i,
      b_address_i => r.read_address,
      b_data_o => read_data_s
      );

end architecture;
