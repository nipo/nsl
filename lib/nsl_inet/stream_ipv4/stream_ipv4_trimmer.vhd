library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use work.stream.all;

entity stream_ipv4_trimmer is
  generic(
    config_c : config_t;
    length_offset_c : natural;
    prefix_length_c : natural;
    min_length_c : natural
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

architecture beh of stream_ipv4_trimmer is

  constant width_c : natural := config_c.data_width;
  -- Widest value the length field can carry, and the resulting bound
  -- of the cut point.
  constant length_max_c : natural := 65535;
  constant cut_max_c : natural
    := nsl_math.arith.max(min_length_c, prefix_length_c + length_max_c);
  -- Every beat but the last of a packet is full width, so the beat
  -- completing the length field always ends at the same byte offset.
  -- That offset is what the resolution cycle measures distances from,
  -- which turns the whole subtraction into a constant term.
  constant resolve_offset_c : natural
    := ((length_offset_c + 1) / width_c + 1) * width_c;
  -- Byte offsets are only tracked until the beat that completes the
  -- length field is consumed, they are cleared afterwards.
  constant offset_max_c : natural := resolve_offset_c;
  -- Cut point distances are measured from the first byte of the beat
  -- following the resolution cycle, hence the two flavors: a beat may
  -- flow during that cycle, or not.
  constant idle_min_c : integer := min_length_c - resolve_offset_c;
  constant idle_base_c : integer := prefix_length_c - resolve_offset_c;
  constant beat_min_c : integer := idle_min_c - width_c;
  constant beat_base_c : integer := idle_base_c - width_c;
  constant distance_min_c : integer
    := nsl_math.arith.min(beat_min_c, beat_base_c);
  subtype distance_t is integer range distance_min_c to cut_max_c;

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c : natural := 2;

  type state_t is (
    -- Length field not complete yet, beats are forwarded as-is
    ST_FIELD,
    -- Cut point distance is computed from the captured length field,
    -- one cycle, a beat may flow meanwhile
    ST_RESOLVE,
    -- Cut point distance is known, beats are cut on match
    ST_ARMED,
    -- Cut beat is withheld until the incoming last beat arrives
    ST_DISCARD
    );

  type regs_t is
  record
    state: state_t;
    -- Byte offset of the first byte of the next incoming beat, only
    -- meaningful until the cut distance is resolved.
    offset: natural range 0 to offset_max_c;
    len_h, len_l: byte;
    -- Byte count from the first byte of the next incoming beat to the
    -- cut point.  Only compared against constants below one beat
    -- width, and decremented by one beat width per accepted beat.
    to_cut: natural range 0 to cut_max_c;
    -- Cut beat, waiting for the incoming last beat to learn its
    -- reject flag.
    hold: master_t;
    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

  -- Byte of the incoming beat sitting at the given packet offset, or
  -- the byte already captured when this beat does not reach it.
  function captured(stored: byte;
                    offset: natural;
                    target: natural;
                    data: byte_string;
                    keep: std_ulogic_vector) return byte
  is
    variable ret: byte := stored;
  begin
    for i in data'range
    loop
      if keep(i) = '1' and offset + i = target then
        ret := data(i);
      end if;
    end loop;
    return ret;
  end function;

  -- Whether the cut point falls on a kept byte of the incoming beat.
  -- The distance is only compared against constants below one beat
  -- width, so only a handful of its bits take part.
  function cut_lands_in(to_cut: natural;
                        keep: std_ulogic_vector) return boolean
  is
    variable ret: boolean := false;
  begin
    for i in keep'range
    loop
      if to_cut = i + 1 and keep(i) = '1' then
        ret := true;
      end if;
    end loop;
    return ret;
  end function;

  -- Keep mask of the cut beat: every byte before the cut point.
  function keep_upto(to_cut: natural) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to width_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_logic(i < to_cut);
    end loop;
    return ret;
  end function;

  -- Beat handed to the fifo, picked among the candidates the state
  -- and the cut point make eligible.
  function beat_select(discarding, cutting: boolean;
                       hold_b, clip_b, pass_b: master_t) return master_t
  is
  begin
    if discarding then
      return hold_b;
    elsif cutting then
      return clip_b;
    else
      return pass_b;
    end if;
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

  assert config_c.has_last
    report "Configuration must have last signal"
    severity failure;
  assert config_c.user_width >= 1
    report "Configuration must have a user bit for the reject flag"
    severity failure;
  -- Resolving the cut distance from the length field takes a cycle of
  -- its own, and one beat may flow during that cycle.  The cut point
  -- must therefore fall past the beat that follows the one completing
  -- the length field.
  assert min_length_c > resolve_offset_c + width_c
    report "Minimum length must be one beat past the beat holding the length field"
    severity failure;

  monitor: process(clock_i) is
  begin
    if rising_edge(clock_i) and reset_n_i = '1' then
      if is_valid(config_c, in_i) then
        assert is_packed(config_c, in_i)
          report "Sparse keep pattern, not supported"
          severity failure;
        -- Once the cut distance is resolved, it is tracked by beats of
        -- a constant size.
        assert r.state = ST_FIELD
          or is_last(config_c, in_i)
          or byte_count(config_c, in_i) = width_c
          report "Partial beat before the last one, not supported"
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
      r.state <= ST_FIELD;
      r.offset <= 0;
      r.len_h <= x"00";
      r.len_l <= x"00";
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable accept_v, push_v, pop_v, last_v, rejected_v, cut_now_v: boolean;
    variable data_v: byte_string(0 to width_c-1);
    variable keep_v, cut_keep_v: std_ulogic_vector(0 to width_c-1);
    variable count_v: natural range 0 to width_c;
    variable off_v: natural range 0 to offset_max_c;
    variable end_v: natural range 0 to offset_max_c + width_c;
    variable len_h_v, len_l_v: byte;
    variable len_v: byte_string(0 to 1);
    variable idle_cut_v, beat_cut_v, to_cut_v: distance_t;
    variable pass_v, clip_v, beat_v: master_t;
  begin
    rin <= r;

    accept_v := is_valid(config_c, in_i) and r.fifo_fillness < fifo_depth_c;
    pop_v := r.fifo_fillness > 0 and is_ready(config_c, out_i);

    data_v := bytes(config_c, in_i);
    keep_v := keep(config_c, in_i);
    count_v := byte_count(config_c, in_i);
    last_v := is_last(config_c, in_i);
    rejected_v := is_rejected(config_c, in_i);

    off_v := r.offset;
    end_v := off_v + count_v;

    len_h_v := captured(r.len_h, off_v, length_offset_c, data_v, keep_v);
    len_l_v := captured(r.len_l, off_v, length_offset_c + 1, data_v, keep_v);

    -- Cut point distance candidates for the beat that follows the
    -- resolution cycle, one per outcome of the handshake during that
    -- cycle.  Both are built from registers only, and the offset they
    -- are measured from is the constant every packet reaches, so the
    -- length field meets one constant term and one adder.  A partial
    -- beat during that cycle ends the packet, the distance is then
    -- unused.
    len_v := (0 => r.len_h, 1 => r.len_l);
    idle_cut_v := idle_base_c + to_integer(from_be(len_v));
    beat_cut_v := beat_base_c + to_integer(from_be(len_v));
    to_cut_v := if_else(accept_v,
                        nsl_math.arith.max(beat_min_c, beat_cut_v),
                        nsl_math.arith.max(idle_min_c, idle_cut_v));

    -- Deciding whether the cut point falls in the incoming beat only
    -- involves the registered distance and constants below one beat
    -- width.
    cut_keep_v := keep_upto(r.to_cut);
    cut_now_v := r.state = ST_ARMED and cut_lands_in(r.to_cut, keep_v);

    -- The beat forwarded whole; its last one closes a packet that
    -- ended before the length its header declares, hence rejected.
    pass_v := reject_set(config_c,
                         transfer(config_c,
                                  bytes => data_v,
                                  keep => keep_v,
                                  user => "0",
                                  valid => true,
                                  last => last_v),
                         last_v);
    -- The beat clipped at the cut point.  Its reject flag is only
    -- final when the packet ends here, the discard state fetches it
    -- from the incoming last beat otherwise.
    clip_v := reject_set(config_c,
                         transfer(config_c,
                                  bytes => data_v,
                                  keep => cut_keep_v,
                                  user => "0",
                                  valid => true,
                                  last => true),
                         rejected_v);
    beat_v := beat_select(r.state = ST_DISCARD, cut_now_v,
                          reject_set(config_c, r.hold, rejected_v),
                          clip_v, pass_v);

    -- The cut beat is the only one that does not reach the fifo right
    -- away, and only while its reject flag is still unknown.
    push_v := accept_v
              and (r.state = ST_FIELD
                   or r.state = ST_RESOLVE
                   or (r.state = ST_ARMED and (last_v or not cut_now_v))
                   or (r.state = ST_DISCARD and last_v));

    case r.state is
      when ST_FIELD =>
        -- The cut point cannot fall in a beat consumed before the
        -- length field is complete.
        if accept_v then
          if last_v then
            rin.offset <= 0;
            rin.len_h <= x"00";
            rin.len_l <= x"00";
          else
            rin.offset <= end_v;
            rin.len_h <= len_h_v;
            rin.len_l <= len_l_v;

            if end_v > length_offset_c + 1 then
              rin.state <= ST_RESOLVE;
            end if;
          end if;
        end if;

      when ST_RESOLVE =>
        assert r.offset = resolve_offset_c
          report "Length field completed at an unexpected offset"
          severity failure;

        if accept_v and last_v then
          rin.state <= ST_FIELD;
          rin.offset <= 0;
          rin.len_h <= x"00";
          rin.len_l <= x"00";
        else
          assert to_cut_v > 0
            report "Cut point resolved after the beat it falls in"
            severity failure;

          rin.state <= ST_ARMED;
          rin.to_cut <= to_cut_v;
          rin.offset <= 0;
        end if;

      when ST_ARMED =>
        if accept_v then
          if cut_now_v then
            rin.len_h <= x"00";
            rin.len_l <= x"00";

            if last_v then
              rin.state <= ST_FIELD;
            else
              rin.hold <= clip_v;
              rin.state <= ST_DISCARD;
            end if;
          elsif last_v then
            rin.state <= ST_FIELD;
            rin.len_h <= x"00";
            rin.len_l <= x"00";
          else
            rin.to_cut <= r.to_cut - width_c;
          end if;
        end if;

      when ST_DISCARD =>
        if accept_v and last_v then
          rin.state <= ST_FIELD;
        end if;
    end case;

    rin.fifo <= fifo_shift_data(r.fifo, r.fifo_fillness,
                                push_v, beat_v, pop_v);
    rin.fifo_fillness <= fifo_shift_fillness(r.fifo_fillness, fifo_depth_c,
                                             push_v, pop_v);
  end process;

  moore: process(r) is
  begin
    in_o <= accept(config_c, r.fifo_fillness < fifo_depth_c);

    if r.fifo_fillness > 0 then
      out_o <= r.fifo(0);
    else
      out_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
