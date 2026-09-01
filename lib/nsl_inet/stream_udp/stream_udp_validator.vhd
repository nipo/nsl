library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_math.int_ext.all;
use work.checksum.all;
use work.ipv4.all;
use work.stream.all;
use work.stream_ipv4.all;
use work.stream_udp.all;

entity stream_udp_validator is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in ipv4_t;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_udp_validator is

  constant width_c : natural := config_c.data_width;
  constant lengths_c : integer_vector(0 to header_length_c'length-1)
    := header_length_c;
  -- Transported size of the blocks forwarded verbatim, the IPv4
  -- context block last.
  constant pre_size_c : integer
    := context_byte_count(config_c, header_length_c);
  constant ip_context_block_c : integer
    := context_byte_count(config_c, (0 => ip_context_length_c));
  -- The IPv4 context is the last of the forwarded blocks, so it
  -- starts one block short of the end of the prefix.
  constant ip_context_offset_c : integer := pre_size_c - ip_context_block_c;

  -- Byte offset of the peer address of the pseudo-header, which the
  -- IPv4 context block carries first.  It takes no latch of its own:
  -- it is folded from the beats that carry it, as the datagram is.
  constant peer_offset_c : integer := ip_context_offset_c;

  -- Byte offsets of the header fields the verdict needs, which are
  -- the only ones latched: the length word, last term of the
  -- pseudo-header, then the checksum field.
  constant length_offset_c : integer := pre_size_c + 4;
  constant checksum_offset_c : integer := pre_size_c + 6;
  constant capture_offset_c : integer_vector(0 to 3)
    := (length_offset_c, length_offset_c + 1,
        checksum_offset_c, checksum_offset_c + 1);

  -- Beat carrying the first checksummed byte, and count of beats up
  -- to the end of the UDP header.  Every block is a whole count of
  -- beats, so the UDP header starts on a beat boundary and so does
  -- the peer address.
  constant pre_beats_c : integer := pre_size_c / width_c;
  constant header_beats_c : integer
    := (pre_size_c + udp_header_length_c) / width_c;

  constant zero_checksum_c : byte_string(0 to 1) := (others => x"00");

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c : integer := 2;

  -- Stages between the accumulator and the fifo.  Beats enter the
  -- first stage and move by one stage per cycle, so a datagram's last
  -- beat reaches the fifo three cycles after being taken in, by which
  -- time its verdict is latched.  Bubbles are not collapsed: that is
  -- what makes the delay a fixed one.
  constant pending_depth_c : integer := 3;

  -- One beat is folded per cycle, whatever the stream width.  A byte
  -- chunk rotates the accumulator instead of padding a partial beat,
  -- so the parity of the datagram decides the alignment the trailing
  -- pseudo-header terms are folded at.
  constant checksum_c : checksum_config_t := checksum_config(config_c);
  constant rotating_c : boolean := width_c mod 2 = 1;

  -- Bytes of a beat the checksum covers: the datagram, and, among the
  -- blocks forwarded verbatim, the peer address of the pseudo-header.
  -- Which region a beat belongs to depends on its index alone, the
  -- beat's own keep pattern only narrows the outcome.
  function covered_keep(beat_index: natural;
                        beat_keep: std_ulogic_vector)
    return std_ulogic_vector
  is
    alias k: std_ulogic_vector(0 to width_c-1) is beat_keep;
    variable ret: std_ulogic_vector(0 to width_c-1);
  begin
    for i in ret'range
    loop
      if beat_index >= pre_beats_c then
        ret(i) := k(i);
      elsif beat_index * width_c + i >= peer_offset_c
        and beat_index * width_c + i < peer_offset_c + 4 then
        ret(i) := k(i);
      else
        ret(i) := '0';
      end if;
    end loop;

    return ret;
  end function;

  -- Folds the covered bytes of one beat.  Uncovered bytes are masked
  -- to zero, the additive identity of an even chunk: the datagram and
  -- the peer address then take one adder rather than two exclusive
  -- ones, and a beat covered by neither leaves the accumulated value
  -- alone.  A byte chunk rotates instead of adding, so there an
  -- uncovered byte has to leave the accumulator untouched.
  function covered_fold(state: checksum_state_t;
                        data: byte_string;
                        covered: std_ulogic_vector)
    return checksum_state_t
  is
    alias d: byte_string(0 to width_c-1) is data;
    alias c: std_ulogic_vector(0 to width_c-1) is covered;
    variable masked_v: byte_string(0 to width_c-1);
  begin
    for i in masked_v'range
    loop
      if c(i) = '1' then
        masked_v(i) := d(i);
      else
        masked_v(i) := x"00";
      end if;
    end loop;

    if rotating_c and c(0) /= '1' then
      return state;
    end if;

    return checksum_update(checksum_c, state, masked_v);
  end function;

  -- Accumulator a beat folds into: the seed at the first beat of a
  -- packet, the running one after.  Both are registers, so this is a
  -- select ahead of the adder rather than a step of its own.
  function fold_base(first: boolean;
                     seeded, running: checksum_state_t)
    return checksum_state_t
  is
  begin
    if first then
      return seeded;
    end if;

    return running;
  end function;

  -- Header fields latched from the beats that carry them.  Each slot
  -- is a two-way select between what it holds and the byte at its
  -- offset, the selects being independent of one another.  A datagram
  -- truncated inside its header leaves stale values behind; such
  -- datagrams do not reach the port dispatch.
  function fields_capture(held: byte_string;
                          beat_index: natural;
                          data: byte_string;
                          beat_keep: std_ulogic_vector)
    return byte_string
  is
    alias h: byte_string(0 to capture_offset_c'length-1) is held;
    alias d: byte_string(0 to width_c-1) is data;
    alias k: std_ulogic_vector(0 to width_c-1) is beat_keep;
    variable ret: byte_string(0 to capture_offset_c'length-1);
  begin
    for i in ret'range
    loop
      if beat_index = capture_offset_c(i) / width_c
        and k(capture_offset_c(i) mod width_c) = '1' then
        ret(i) := d(capture_offset_c(i) mod width_c);
      else
        ret(i) := h(i);
      end if;
    end loop;

    return ret;
  end function;

  -- Alignment the length word of the pseudo-header is folded at.
  -- After an odd count of datagram bytes a byte chunk leaves the
  -- accumulator scaled by 256; the length word byte-swapped is that
  -- same word seen from the other alignment, which compensates
  -- without a realigning step.
  function length_term(odd: boolean; fields: byte_string)
    return byte_string
  is
    alias f: byte_string(0 to capture_offset_c'length-1) is fields;
  begin
    if odd then
      return f(1 to 1) & f(0 to 0);
    end if;

    return f(0 to 1);
  end function;

  -- Only a last beat carries the reject flag, the others go through
  -- untouched.
  function verdict_apply(beat: master_t; rejected: boolean)
    return master_t
  is
  begin
    if is_last(config_c, beat) then
      return reject_set(config_c, beat, rejected);
    end if;

    return beat;
  end function;

  type regs_t is
  record
    beat: natural range 0 to header_beats_c;
    -- Pseudo-header terms the datagram does not carry are folded
    -- outside the beat path, in two steps, so that neither carries a
    -- chain longer than the beat path itself.
    seed: checksum_state_t;
    seeded: checksum_state_t;
    acc: checksum_state_t;
    -- acc with the length word of the pseudo-header folded in, one
    -- beat behind acc.  The length is the last term to fold and the
    -- datagram carries it, so folding it at verdict time would put
    -- its adder, the reduction and the comparison in one cycle.  Held
    -- here, it is one adder between two registers, and the verdict
    -- keeps the reduction alone.
    acc_len: checksum_state_t;
    -- Odd count of checksummed bytes folded into acc so far
    odd: boolean;
    fields: byte_string(0 to capture_offset_c'length-1);
    -- Verdict of the datagram whose last beat has been taken in.
    -- acc_len covers that beat on the second cycle after it, and only
    -- until the next datagram takes the accumulator over, so the
    -- verdict is latched on that cycle rather than recomputed.  The
    -- checksum field being present is captured with the beat itself,
    -- fields having moved on by then.
    verdict_c1: boolean;
    verdict_c2: boolean;
    verdict_present: boolean;
    verdict_reject: boolean;
    -- Beats whose contribution to the accumulator is already
    -- registered, awaiting the verdict that rides on their last one
    pending: master_vector(0 to pending_depth_c-1);
    pending_valid: std_ulogic_vector(0 to pending_depth_c-1);
    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

  function fifo_shift_data(fifo: master_vector;
                           fillness: natural;
                           push: boolean;
                           push_data: master_t;
                           pop: boolean) return master_vector
  is
    variable ret: master_vector(0 to fifo'length-1) := fifo;
    variable can_push, can_pop: boolean;
  begin
    can_push := push and fillness < ret'length;
    can_pop := pop and fillness > 0;

    if can_pop then
      for i in 0 to ret'length-2
      loop
        ret(i) := ret(i+1);
      end loop;
      ret(ret'length-1) := transfer_defaults(config_c);
    end if;

    if can_push then
      if can_pop then
        ret(fillness-1) := push_data;
      else
        ret(fillness) := push_data;
      end if;
    end if;

    return ret;
  end function;

  function fifo_shift_fillness(fillness: natural;
                               depth: natural;
                               push: boolean;
                               pop: boolean) return natural
  is
    variable can_push, can_pop: boolean;
  begin
    can_push := push and fillness < depth;
    can_pop := pop and fillness > 0;

    if can_push and not can_pop then
      return fillness + 1;
    elsif can_pop and not can_push then
      return fillness - 1;
    else
      return fillness;
    end if;
  end function;

begin

  assert lengths_c'length > 0
    and lengths_c(lengths_c'right) = ip_context_length_c
    report "Last forwarded block must be the IPv4 context"
    severity failure;

  assert peer_offset_c mod width_c = 0
    report "IPv4 context block must start on a beat boundary"
    severity failure;

  monitor: process(clock_i) is
  begin
    if rising_edge(clock_i) and reset_n_i = '1' then
      if is_valid(config_c, in_i) then
        assert is_packed(config_c, in_i)
          report "Sparse keep pattern, not supported"
          severity failure;
      end if;
    end if;
  end process;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.beat <= 0;
      r.seed <= checksum_init(checksum_c);
      r.seeded <= checksum_init(checksum_c);
      r.acc <= checksum_init(checksum_c);
      r.acc_len <= checksum_init(checksum_c);
      r.odd <= false;
      r.verdict_c1 <= false;
      r.verdict_c2 <= false;
      r.pending_valid <= (others => '0');
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i, local_address_i) is
    variable push_v, advance_v, drain_v, pop_v, last_v: boolean;
    variable data_v: byte_string(0 to width_c-1);
    variable keep_v, covered_v: std_ulogic_vector(0 to width_c-1);
    variable fields_v: byte_string(0 to capture_offset_c'length-1);
    variable acc_v: checksum_state_t;
    variable odd_v: boolean;
    variable entry_v: master_t;
  begin
    rin <= r;

    -- RFC 768 pseudo-header: source and destination addresses, a
    -- zero byte, the protocol number, and the UDP length.  The
    -- datagram reaches this layer from its peer, so the peer address
    -- is the source one.  The sum is commutative and every one of
    -- these groups is an even count of bytes, so each is folded
    -- wherever its operands settle as long as it lands on a 16-bit
    -- boundary: the local address and the protocol here, the peer
    -- address on the beats carrying it, the length one beat behind
    -- the accumulator.  local_address_i is a configuration input, the
    -- cycles the seed takes to settle after a change belong to no
    -- datagram.
    rin.seed <= checksum_update(checksum_c, checksum_init(checksum_c),
                                local_address_i);
    rin.seeded <= checksum_update(checksum_c, r.seed,
                                  to_be(to_unsigned(ip_proto_udp, 16)));

    -- The stages move as one, so a beat takes as many cycles to cross
    -- them as there are stages, whatever the traffic ahead of it.
    drain_v := r.pending_valid(pending_depth_c-1) = '1'
               and r.fifo_fillness < fifo_depth_c;
    advance_v := r.pending_valid(pending_depth_c-1) = '0' or drain_v;
    push_v := is_valid(config_c, in_i) and advance_v;
    pop_v := r.fifo_fillness > 0 and is_ready(config_c, out_i);
    last_v := is_last(config_c, in_i);

    data_v := bytes(config_c, in_i);
    keep_v := keep(config_c, in_i);
    covered_v := covered_keep(r.beat, keep_v);
    fields_v := fields_capture(r.fields, r.beat, data_v, keep_v);

    -- One masked fold serves every region of the packet, so the beat
    -- path holds a single adder between the accumulator and itself.
    acc_v := covered_fold(fold_base(r.beat = 0, r.seeded, r.acc),
                          data_v, covered_v);
    -- The peer address is an even count of bytes, so the beats
    -- carrying it hand the datagram the alignment they found.
    odd_v := rotating_c
             and ((r.beat /= 0 and r.odd) xor (covered_v(0) = '1'));

    rin.acc_len <= checksum_update(checksum_c, r.acc,
                                   length_term(r.odd, r.fields));

    -- acc_len covers a datagram on the second cycle after its last
    -- beat is taken in, one cycle before that beat leaves the stages.
    rin.verdict_c1 <= push_v and last_v;
    rin.verdict_c2 <= r.verdict_c1;
    if push_v and last_v then
      rin.verdict_present <= fields_v(2 to 3) /= zero_checksum_c;
    end if;
    if r.verdict_c2 then
      rin.verdict_reject <= r.verdict_present
                            and not checksum_is_valid(checksum_c, r.acc_len);
    end if;

    entry_v := verdict_apply(r.pending(pending_depth_c-1),
                             is_rejected(config_c,
                                         r.pending(pending_depth_c-1))
                             or r.verdict_reject);

    if advance_v then
      for i in pending_depth_c-1 downto 1
      loop
        rin.pending(i) <= r.pending(i-1);
        rin.pending_valid(i) <= r.pending_valid(i-1);
      end loop;
      rin.pending(0) <= in_i;
      if push_v then
        rin.pending_valid(0) <= '1';
      else
        rin.pending_valid(0) <= '0';
      end if;
    end if;

    if push_v then
      rin.fields <= fields_v;
      rin.acc <= acc_v;
      rin.odd <= odd_v;

      if last_v then
        rin.beat <= 0;
      elsif r.beat /= header_beats_c then
        rin.beat <= r.beat + 1;
      end if;
    end if;

    rin.fifo <= fifo_shift_data(r.fifo, r.fifo_fillness,
                                drain_v, entry_v, pop_v);
    rin.fifo_fillness <= fifo_shift_fillness(r.fifo_fillness, fifo_depth_c,
                                             drain_v, pop_v);
  end process;

  moore: process(r) is
  begin
    in_o <= accept(config_c,
                   r.pending_valid(pending_depth_c-1) = '0'
                   or r.fifo_fillness < fifo_depth_c);

    if r.fifo_fillness > 0 then
      out_o <= r.fifo(0);
    else
      out_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
