library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_memory, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.ncm.all;

entity ncm_transmitter is
  generic(
    frame_config_c : config_t;
    ntb_config_c : config_t;
    ntb_max_size_c : positive := 16384;
    datagram_max_size_c : positive := 1514;
    datagram_max_count_c : positive := 32;
    zlp_avoid_size_c : natural := 64
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    frame_i : in master_t;
    frame_o : out slave_t;

    ntb_o : out master_t;
    ntb_i : in slave_t;

    stats_o : out ncm_transmitter_stats_t
    );
end entity;

-- Two stages around a two-buffer RAM of 16-bit words:
--
-- * the fill stage writes frames, byte-wise (byte write enables), into
--   the buffer it owns, each on a 4-byte boundary after the NTH16 room,
--   and records their index and length; closing a block writes the
--   NDP16 after the datagrams and the NTH16 at offset 0, one word per
--   cycle, then hands the buffer over;
--
-- * the send stage reads the words of a full buffer into a small byte
--   queue, from which NTB beats are built. Reads take two cycles
--   (address register, RAM), tracked by a two-entry tag pipeline; a
--   credit on the queue keeps the reads in flight from overflowing it.
architecture beh of ncm_transmitter is

  constant frame_width_c : natural := frame_config_c.data_width;
  constant ntb_width_c : natural := ntb_config_c.data_width;
  constant word_addr_size_c : natural := nsl_math.arith.log2(ntb_max_size_c / 2);
  constant addr_size_c : natural := word_addr_size_c + 1;
  constant word_count_c : natural := 2 ** word_addr_size_c;
  constant queue_depth_c : natural := 8;
  constant ethernet_header_size_c : natural := 14;
  constant has_user_c : boolean := frame_config_c.user_width >= 1;
  -- NTH16 fields as words, NDP16 header words
  constant nth16_header_words_c : natural := ncm_nth16_length_c / 2;
  constant ndp16_header_words_c : natural := 4;

  subtype offset_t is natural range 0 to 65535;
  type offset_vector is array(natural range <>) of offset_t;
  subtype word_index_t is natural range 0 to word_count_c-1;

  -- NDP16 size for n datagrams: header, n entries, the zero entry.
  function ndp_size(n : natural) return natural
  is
  begin
    return 8 + 4 * (n + 1);
  end function;

  type fill_state_t is (
    FILL_IDLE,
    FILL_DATA,
    FILL_CLOSE
    );

  type send_state_t is (
    SEND_IDLE,
    SEND_READ,
    SEND_DRAIN
    );

  type tag_t is
  record
    valid, last : boolean;
  end record;
  constant tag_none_c : tag_t := (false, false);
  type tag_vector is array(natural range <>) of tag_t;

  type queue_t is array(0 to queue_depth_c-1) of byte;

  type regs_t is
  record
    -- Fill
    fill_state : fill_state_t;
    fill_buffer : natural range 0 to 1;
    next_offset : offset_t;             -- where the next datagram goes
    datagram_count : natural range 0 to datagram_max_count_c;
    entry_index : offset_vector(0 to datagram_max_count_c-1);
    entry_length : offset_vector(0 to datagram_max_count_c-1);
    start : offset_t;
    length : natural range 0 to 4095;
    bad : boolean;
    close_word : natural range 0 to 2 * datagram_max_count_c + 12;
    close_last : natural range 0 to 2 * datagram_max_count_c + 12;
    ndp_offset : offset_t;
    ndp_length : offset_t;
    block_size : offset_t;
    sequence : unsigned(15 downto 0);
    write_en : std_ulogic_vector(1 downto 0);
    write_address : unsigned(addr_size_c-1 downto 0);
    write_data : byte_string(0 to 1);

    -- Buffers
    full : std_ulogic_vector(0 to 1);
    block_length : offset_vector(0 to 1);

    -- Send
    send_state : send_state_t;
    send_buffer : natural range 0 to 1;
    send_word : word_index_t;
    send_end_word : word_index_t;
    read_address : unsigned(addr_size_c-1 downto 0);
    tag : tag_vector(0 to 1);

    -- Byte queue towards ntb_o
    queue : queue_t;
    queue_last : std_ulogic_vector(0 to queue_depth_c-1);
    queue_read : natural range 0 to queue_depth_c-1;
    queue_count : natural range 0 to queue_depth_c;

    stats : ncm_transmitter_stats_t;
  end record;

  signal r, rin : regs_t;
  signal read_data_s : std_ulogic_vector(15 downto 0);

  function le16(v : natural) return byte_string
  is
    variable u : unsigned(15 downto 0) := to_unsigned(v, 16);
  begin
    return (0 => std_ulogic_vector(u(7 downto 0)),
            1 => std_ulogic_vector(u(15 downto 8)));
  end function;

  function word_address(buf : natural; word : natural) return unsigned
  is
  begin
    return to_unsigned(buf, 1) & to_unsigned(word, word_addr_size_c);
  end function;

  function zero_stats return ncm_transmitter_stats_t
  is
  begin
    return (others => (others => '0'));
  end function;

begin

  assert ntb_width_c = 1 or ntb_width_c = 2
    report "NTB stream must be 1 or 2 bytes wide"
    severity failure;
  assert frame_width_c = 1 or frame_width_c = 2
    report "Frame stream must be 1 or 2 bytes wide"
    severity failure;
  assert ntb_config_c.has_last
    report "NTB stream must have a last signal"
    severity failure;
  assert frame_config_c.has_last
    report "Frame stream must have a last signal"
    severity failure;
  assert ntb_max_size_c = 2 * word_count_c and ntb_max_size_c <= 65536
    report "ntb_max_size_c must be a power of two, at most 65536"
    severity failure;
  assert ncm_nth16_length_c + datagram_max_size_c + 3
    + ndp_size(1) + 4 <= ntb_max_size_c
    report "ntb_max_size_c too small for one datagram"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.fill_state <= FILL_IDLE;
      r.fill_buffer <= 0;
      r.next_offset <= ncm_nth16_length_c;
      r.datagram_count <= 0;
      r.sequence <= (others => '0');
      r.write_en <= "00";
      r.full <= "00";
      r.send_state <= SEND_IDLE;
      r.send_buffer <= 0;
      r.tag <= (others => tag_none_c);
      r.queue_read <= 0;
      r.queue_count <= 0;
      r.stats <= zero_stats;
    end if;
  end process;

  transition: process(r, frame_i, ntb_i, read_data_s) is
    variable full_v : std_ulogic_vector(0 to 1);
    variable stats_v : ncm_transmitter_stats_t;
    variable fits_v, last_v, rejected_v : boolean;
    variable in_bytes_v : byte_string(0 to frame_width_c-1);
    variable in_count_v : natural range 0 to frame_width_c;
    variable length_v : natural range 0 to 4095;
    variable block_size_v : offset_t;
    variable offset_v : offset_t;
    variable word_v : byte_string(0 to 1);
    variable address_v : natural;
    variable entry_v : natural range 0 to datagram_max_count_c-1;
    variable k_v : natural;
    variable issue_v : tag_t;
    variable inflight_v : natural range 0 to 2;
    -- queue
    variable queue_v : queue_t;
    variable queue_last_v : std_ulogic_vector(0 to queue_depth_c-1);
    variable queue_read_v : natural range 0 to queue_depth_c-1;
    variable queue_count_v : natural range 0 to queue_depth_c;

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

    -- NTB beat taken by the consumer (blocks are whole words: always full)
    if r.queue_count >= ntb_width_c and is_ready(ntb_config_c, ntb_i) then
      queue_read_v := (queue_read_v + ntb_width_c) mod queue_depth_c;
      queue_count_v := queue_count_v - ntb_width_c;
    end if;

    ------------------------------------------------------------------- fill
    rin.write_en <= "00";
    rin.write_address <= (others => '-');
    rin.write_data <= (others => dontcare_byte_c);

    case r.fill_state is
      when FILL_IDLE =>
        if r.full(r.fill_buffer) = '0' then
          -- Room for a maximum frame (plus alignment), the NDP with one
          -- more entry, and the ZLP-avoidance pad?
          fits_v := r.datagram_count < datagram_max_count_c
                    and r.next_offset + datagram_max_size_c + 3
                        + ndp_size(r.datagram_count + 1) + 4 <= ntb_max_size_c;
          if r.datagram_count /= 0
            and (not fits_v
                 or (not is_valid(frame_config_c, frame_i)
                     and r.full(1 - r.fill_buffer) = '0')) then
            -- Close: NDP right after the datagrams (next_offset is
            -- 4-aligned), then the header.
            block_size_v := r.next_offset + ndp_size(r.datagram_count);
            if zlp_avoid_size_c /= 0 and block_size_v mod zlp_avoid_size_c = 0 then
              block_size_v := block_size_v + 4;
            end if;
            rin.ndp_offset <= r.next_offset;
            rin.ndp_length <= ndp_size(r.datagram_count);
            rin.block_size <= block_size_v;
            rin.close_word <= 0;
            rin.close_last <= ndp16_header_words_c + 2 * r.datagram_count + 2
                              + nth16_header_words_c - 1;
            rin.fill_state <= FILL_CLOSE;
          elsif is_valid(frame_config_c, frame_i) then
            rin.start <= r.next_offset;
            rin.length <= 0;
            rin.bad <= false;
            rin.fill_state <= FILL_DATA;
          end if;
        end if;

      when FILL_DATA =>
        -- frame_o is ready in this state.
        if is_valid(frame_config_c, frame_i) then
          in_bytes_v := bytes(frame_config_c, frame_i);
          in_count_v := byte_count(frame_config_c, frame_i);
          last_v := is_last(frame_config_c, frame_i);
          length_v := r.length;

          -- start is even and only the last beat can be short, so the
          -- bytes of a beat fall in one word.
          if r.length < datagram_max_size_c then
            offset_v := r.start + r.length;
            rin.write_address <= word_address(r.fill_buffer, offset_v / 2);
            for i in 0 to frame_width_c-1
            loop
              if i < in_count_v then
                rin.write_en((offset_v + i) mod 2) <= '1';
                rin.write_data((offset_v + i) mod 2) <= in_bytes_v(i);
              end if;
            end loop;
          else
            rin.bad <= true;
          end if;
          if length_v + in_count_v <= 4095 then
            length_v := length_v + in_count_v;
          end if;
          rin.length <= length_v;

          if last_v then
            rejected_v := false;
            if has_user_c then
              rejected_v := user(frame_config_c, frame_i)(0) = '1';
            end if;
            if r.bad or length_v > datagram_max_size_c
              or length_v < ethernet_header_size_c or rejected_v then
              stats_v.drop_count := stats_v.drop_count + 1;
            else
              rin.entry_index(r.datagram_count) <= r.start;
              rin.entry_length(r.datagram_count) <= length_v;
              rin.datagram_count <= r.datagram_count + 1;
              -- next datagram on a 4-byte boundary
              rin.next_offset <= ((r.start + length_v + 3) / 4) * 4;
              stats_v.datagram_count := stats_v.datagram_count + 1;
            end if;
            rin.fill_state <= FILL_IDLE;
          end if;
        end if;

      when FILL_CLOSE =>
        -- One word per cycle: NDP16 (signature, wLength, wNextNdpIndex),
        -- the entries, the zero entry, then the NTH16 at word 0.
        k_v := r.close_word;
        if k_v < ndp16_header_words_c then
          address_v := r.ndp_offset / 2 + k_v;
          case k_v is
            when 0 => word_v := ncm_ndp16_signature_c(0 to 1);
            when 1 => word_v := ncm_ndp16_signature_c(2 to 3);
            when 2 => word_v := le16(r.ndp_length);
            when others => word_v := le16(0);
          end case;
        elsif k_v < ndp16_header_words_c + 2 * r.datagram_count then
          address_v := r.ndp_offset / 2 + k_v;
          entry_v := (k_v - ndp16_header_words_c) / 2;
          if (k_v mod 2) = 0 then
            word_v := le16(r.entry_index(entry_v));
          else
            word_v := le16(r.entry_length(entry_v));
          end if;
        elsif k_v < ndp16_header_words_c + 2 * r.datagram_count + 2 then
          address_v := r.ndp_offset / 2 + k_v;
          word_v := le16(0);
        else
          address_v := k_v - (ndp16_header_words_c + 2 * r.datagram_count + 2);
          case address_v is
            when 0 => word_v := ncm_nth16_signature_c(0 to 1);
            when 1 => word_v := ncm_nth16_signature_c(2 to 3);
            when 2 => word_v := le16(ncm_nth16_length_c);
            when 3 => word_v := le16(to_integer(r.sequence));
            when 4 => word_v := le16(r.block_size);
            when others => word_v := le16(r.ndp_offset);
          end case;
        end if;
        rin.write_en <= "11";
        rin.write_address <= word_address(r.fill_buffer, address_v);
        rin.write_data <= word_v;

        if k_v = r.close_last then
          rin.block_length(r.fill_buffer) <= r.block_size;
          full_v(r.fill_buffer) := '1';
          rin.fill_buffer <= 1 - r.fill_buffer;
          rin.sequence <= r.sequence + 1;
          rin.datagram_count <= 0;
          rin.next_offset <= ncm_nth16_length_c;
          stats_v.ntb_count := stats_v.ntb_count + 1;
          rin.fill_state <= FILL_IDLE;
        else
          rin.close_word <= k_v + 1;
        end if;
    end case;

    ------------------------------------------------------------------- send
    if r.tag(1).valid then
      word_v := (0 => read_data_s(7 downto 0), 1 => read_data_s(15 downto 8));
      push(word_v(0), false);
      push(word_v(1), r.tag(1).last);
    end if;

    issue_v := tag_none_c;
    inflight_v := 0;
    if r.tag(0).valid then
      inflight_v := 2;
    end if;

    case r.send_state is
      when SEND_IDLE =>
        -- r.full: the block length is registered along with it.
        if r.full(r.send_buffer) = '1' then
          rin.send_word <= 0;
          rin.send_end_word <= r.block_length(r.send_buffer) / 2 - 1;
          rin.send_state <= SEND_READ;
        end if;

      when SEND_READ =>
        if queue_count_v + inflight_v + 2 <= queue_depth_c then
          issue_v := (true, r.send_word = r.send_end_word);
          rin.read_address <= word_address(r.send_buffer, r.send_word);
          if r.send_word = r.send_end_word then
            rin.send_state <= SEND_DRAIN;
          else
            rin.send_word <= r.send_word + 1;
          end if;
        end if;

      when SEND_DRAIN =>
        if not r.tag(0).valid and not r.tag(1).valid then
          full_v(r.send_buffer) := '0';
          rin.send_buffer <= 1 - r.send_buffer;
          rin.send_state <= SEND_IDLE;
        end if;
    end case;

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
    variable bytes_v : byte_string(0 to ntb_width_c-1);
    variable last_v : boolean;
  begin
    frame_o <= accept(frame_config_c, r.fill_state = FILL_DATA);
    stats_o <= r.stats;

    bytes_v := (others => dontcare_byte_c);
    last_v := false;
    if r.queue_count >= ntb_width_c then
      for i in 0 to ntb_width_c-1
      loop
        bytes_v(i) := r.queue((r.queue_read + i) mod queue_depth_c);
        last_v := r.queue_last((r.queue_read + i) mod queue_depth_c) = '1';
      end loop;
      ntb_o <= transfer(ntb_config_c,
                        bytes => bytes_v,
                        valid => true,
                        last => last_v);
    else
      ntb_o <= transfer(ntb_config_c,
                        bytes => bytes_v,
                        valid => false);
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
