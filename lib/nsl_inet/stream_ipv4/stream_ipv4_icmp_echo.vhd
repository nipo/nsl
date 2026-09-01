library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.checksum.all;
use work.stream.all;

entity stream_ipv4_icmp_echo is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_ipv4_icmp_echo is

  constant width_c: natural := config_c.data_width;
  -- Blocks forwarded verbatim, the layer-3 context included.  Every
  -- block spans a whole count of beats, so the PDU starts on a beat
  -- boundary.
  constant pdu_offset_c: natural
    := context_byte_count(config_c, header_length_c);
  constant prefix_beats_c: natural := pdu_offset_c / width_c;
  -- Type, code and checksum: the fields the decision and the rewrite
  -- need.  A PDU shorter than this cannot be answered.
  constant icmp_header_length_c: natural := 4;
  constant header_beats_c: natural
    := (icmp_header_length_c + width_c - 1) / width_c;
  constant decision_beats_c: natural := prefix_beats_c + header_beats_c;
  -- Kept bytes the last beat of the ICMP header must carry for the
  -- checksum field to be complete.
  constant last_header_bytes_c: natural
    := icmp_header_length_c - (header_beats_c - 1) * width_c;
  -- Beats withheld from the output until the type is known, plus room
  -- for the decision cycle and the registered handshake.  Past this
  -- constant, input ready only follows output readiness.
  constant fifo_depth_c: natural := decision_beats_c + 2;

  -- One beat is folded per cycle, whatever the stream width.
  constant checksum_c: checksum_config_t := checksum_config(config_c);

  constant echo_request_type_c: byte := to_byte(8);
  constant echo_reply_type_c: byte := to_byte(0);
  constant echo_code_c: byte := to_byte(0);
  -- The stored checksum is the complement of the sum, so clearing the
  -- type byte, high half of the first word of the PDU, raises it by
  -- 0x0800 with end-around carry.  Both outcomes of that carry are
  -- computed side by side and the carry picks between them, which
  -- keeps the rewrite one adder deep.
  constant checksum_delta_c: unsigned(16 downto 0)
    := to_unsigned(16#0800#, 17);
  constant checksum_carried_c: unsigned(16 downto 0)
    := to_unsigned(16#0801#, 17);

  type state_t is (
    -- Withholding the start of a packet from the output until the
    -- ICMP header tells whether to answer it.
    ST_FILL,
    -- Answering: accepted beats reach the output as they come.
    ST_PASS,
    -- Consuming a packet that gets no answer.
    ST_DROP
    );

  type regs_t is
  record
    state: state_t;
    in_beat: natural range 0 to decision_beats_c;
    checksum: checksum_state_t;
    -- ICMP header bytes seen so far, shifted in from the tail: the
    -- whole header sits here once the decision beat is registered, no
    -- byte indexing involved.
    icmp_header: byte_string(0 to icmp_header_length_c-1);

    -- Beat whose contribution to the accumulator and to the header
    -- capture is already registered, awaiting its fifo slot.  The
    -- decision and the checksum verdict are taken on it, from
    -- registers only.
    pending: master_t;
    pending_valid: boolean;
    -- The pending beat is the one completing the ICMP header.
    pending_decision: boolean;

    -- Beats reach the fifo before the packet they belong to is
    -- qualified.  fifo_visible counts those at the head a decision
    -- committed to the output; the ones above are withdrawn by
    -- rewinding fifo_fillness to fifo_visible.
    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
    fifo_visible: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

  -- The checksum covers the PDU only, the forwarded blocks are
  -- outside it.  The accumulator is seeded on the first PDU beat
  -- rather than cleared on the last one: the verdict is taken one
  -- cycle after the last beat is folded, so the value has to outlive
  -- the packet by a cycle.
  function pdu_checksum(state: checksum_state_t;
                        beat: master_t;
                        in_beat: natural) return checksum_state_t
  is
    variable base: checksum_state_t := state;
  begin
    if in_beat < prefix_beats_c then
      return state;
    end if;

    if in_beat = prefix_beats_c then
      base := checksum_init(checksum_c);
    end if;

    return checksum_update(checksum_c, base, config_c, beat);
  end function;

  -- Reject flags only live on last beats; other beats travel
  -- untouched.
  function last_reject_set(cfg: config_t;
                           m: master_t;
                           rejected: boolean) return master_t
  is
  begin
    if is_last(cfg, m) then
      return reject_set(cfg, m, rejected);
    end if;
    return m;
  end function;

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

  -- A rewind drops everything above the committed head; otherwise the
  -- fifo grows by the pushed beat and shrinks by the popped one.
  function fifo_fillness_next(fillness, visible: natural;
                              rewind, push, pop: boolean) return natural
  is
    constant taken_c: integer := if_else(pop, 1, 0);
  begin
    if rewind then
      return visible - taken_c;
    end if;
    return fillness + if_else(push, 1, 0) - taken_c;
  end function;

  -- A commit makes the whole fifo visible, the beat pushed alongside
  -- included; past that the packet streams through.
  function fifo_visible_next(fillness, visible: natural;
                             commit, advance, pop: boolean) return natural
  is
    constant taken_c: integer := if_else(pop, 1, 0);
  begin
    if commit then
      return fillness + 1 - taken_c;
    elsif advance then
      return visible + 1 - taken_c;
    end if;
    return visible - taken_c;
  end function;

begin

  -- Header capture and rewrite assume the ICMP header spans a whole
  -- count of beats.
  assert width_c = 1 or width_c = 2 or width_c = 4
    report "Data width must be 1, 2 or 4 bytes"
    severity failure;
  assert config_c.has_last and config_c.has_keep and config_c.user_width >= 1
    report "Configuration must have last, keep and a user bit"
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
      r.state <= ST_FILL;
      r.in_beat <= 0;
      r.checksum <= checksum_init(checksum_c);
      r.pending_valid <= false;
      r.fifo_fillness <= 0;
      r.fifo_visible <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable last_v, accepted_v, drain_v, push_v, pop_v: boolean;
    variable pending_last_v, in_header_v, valid_v: boolean;
    variable decide_v, answerable_v, commit_v, rewind_v: boolean;
    variable data_v: byte_string(0 to width_c-1);
    variable header_v, reply_v: byte_string(0 to icmp_header_length_c-1);
    variable acc_v: checksum_state_t;
    variable beat_v: master_t;
    variable raised_v, carried_v: unsigned(16 downto 0);
    variable checksum_v: unsigned(15 downto 0);
    variable slot_v: natural range 0 to fifo_depth_c;
  begin
    rin <= r;

    -- The pending beat leaves for its fifo slot as soon as there is
    -- one; a dropped packet needs none.  Input ready follows, it is a
    -- function of the registers only.
    drain_v := r.pending_valid
               and (r.fifo_fillness < fifo_depth_c or r.state = ST_DROP);
    accepted_v := is_valid(config_c, in_i)
                  and (not r.pending_valid or drain_v);
    push_v := drain_v and r.state /= ST_DROP;
    pop_v := r.fifo_visible /= 0 and is_ready(config_c, out_i);

    last_v := is_last(config_c, in_i);
    pending_last_v := is_last(config_c, r.pending);
    data_v := bytes(config_c, in_i);

    in_header_v := prefix_beats_c <= r.in_beat
                   and r.in_beat < decision_beats_c;
    header_v := r.icmp_header(width_c to icmp_header_length_c-1) & data_v;
    acc_v := pdu_checksum(r.checksum, in_i, r.in_beat);

    if accepted_v then
      rin.pending <= in_i;
      rin.pending_valid <= true;
      rin.pending_decision <= r.in_beat = decision_beats_c - 1;
      rin.checksum <= acc_v;

      if in_header_v then
        rin.icmp_header <= header_v;
      end if;

      if last_v then
        rin.in_beat <= 0;
      elsif r.in_beat /= decision_beats_c then
        rin.in_beat <= r.in_beat + 1;
      end if;
    elsif drain_v then
      rin.pending_valid <= false;
    end if;

    -- Verdict of the pending beat, its own contribution to the
    -- accumulator already registered.
    valid_v := checksum_is_valid(checksum_c, r.checksum);
    beat_v := last_reject_set(config_c, r.pending,
                              is_rejected(config_c, r.pending)
                              or not valid_v);

    -- A truncated packet, or a message this endpoint does not answer,
    -- leaves only the withheld beats to withdraw.
    decide_v := drain_v and r.state = ST_FILL and r.pending_decision;
    answerable_v := (not pending_last_v
                     or byte_count(config_c, r.pending)
                        >= last_header_bytes_c)
                    and r.icmp_header(0) = echo_request_type_c
                    and r.icmp_header(1) = echo_code_c;
    commit_v := decide_v and answerable_v;
    rewind_v := drain_v and r.state = ST_FILL and not commit_v
                and (pending_last_v or r.pending_decision);

    raised_v := resize(from_be(r.icmp_header(2 to 3)), 17) + checksum_delta_c;
    carried_v := resize(from_be(r.icmp_header(2 to 3)), 17)
                 + checksum_carried_c;
    checksum_v := if_else(raised_v(16) = '1',
                          carried_v(15 downto 0), raised_v(15 downto 0));
    reply_v := byte_string'(0 => echo_reply_type_c, 1 => r.icmp_header(1))
               & to_be(checksum_v);
    slot_v := if_else(pop_v, r.fifo_fillness - 1, r.fifo_fillness);

    case r.state is
      when ST_FILL =>
        if commit_v and not pending_last_v then
          rin.state <= ST_PASS;
        elsif rewind_v and not pending_last_v then
          rin.state <= ST_DROP;
        end if;

      when ST_PASS | ST_DROP =>
        if drain_v and pending_last_v then
          rin.state <= ST_FILL;
        end if;
    end case;

    rin.fifo_fillness <= fifo_fillness_next(r.fifo_fillness, r.fifo_visible,
                                            rewind_v, push_v, pop_v);
    rin.fifo_visible <= fifo_visible_next(r.fifo_fillness, r.fifo_visible,
                                          commit_v,
                                          push_v and r.state = ST_PASS,
                                          pop_v);
    rin.fifo <= fifo_shift_data(r.fifo, r.fifo_fillness,
                                push_v, beat_v, pop_v);

    -- The ICMP header beats are the topmost ones of the fifo when the
    -- decision beat lands: rewriting them there keeps the answer with
    -- the packet, whatever else the fifo holds.
    if commit_v then
      for j in 0 to header_beats_c-1
      loop
        rin.fifo(slot_v - (header_beats_c-1 - j)).data(0 to width_c-1)
          <= reply_v(j * width_c to j * width_c + width_c - 1);
      end loop;
    end if;
  end process;

  moore: process(r) is
  begin
    in_o <= accept(config_c,
                   not r.pending_valid
                   or r.fifo_fillness < fifo_depth_c
                   or r.state = ST_DROP);

    if r.fifo_visible /= 0 then
      out_o <= r.fifo(0);
    else
      out_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
