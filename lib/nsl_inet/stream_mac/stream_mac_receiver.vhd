library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, nsl_inet, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use work.mac.all;
use work.stream_mac.all;

entity stream_mac_receiver is
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

architecture beh of stream_mac_receiver is

  constant width_c: natural := config_c.data_width;
  constant fcs_size_c: natural := crc_byte_length(fcs_params_c);
  constant min_frame_size_c: natural := 64;

  -- Bytes preceding the first ethernet header byte: the forwarded
  -- blocks, then the front pad of the frame block.
  constant skip_size_c: natural := context_byte_count(config_c, header_length_c)
                                   + ethernet_frame_offset(config_c);
  -- Beats fully covered by the skipped bytes, then the skipped bytes
  -- remaining in the beat that starts the ethernet header.
  constant skip_beat_count_c: natural := skip_size_c / width_c;
  constant skip_byte_count_c: natural := skip_size_c mod width_c;

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c: natural := 2;

  subtype beat_bytes_t is byte_string(0 to width_c-1);
  subtype beat_keep_t is std_ulogic_vector(0 to width_c-1);
  -- The bytes withheld so far, followed by the ones a beat brings.
  subtype window_t is byte_string(0 to fcs_size_c+width_c-1);

  -- The stream crosses three stages, each doing one register-to-register
  -- hop:
  --
  -- * trim, which withholds the trailing bytes that may turn out to be
  --   the FCS and slides the bytes the FCS covers to the start of the
  --   beat,
  --
  -- * fold, which folds those bytes into the FCS and counts the frame
  --   down to the minimum size,
  --
  -- * check, which turns the folded state into the reject flag and
  --   pushes the beat to the output fifo.
  --
  -- Only the stage that owns a piece of state ever computes it, so no
  -- stage feeds another one within a cycle.
  type regs_t is
  record
    -- Trim stage.  The hold carries the last fcs_size_c bytes of the
    -- packet, the newest one last; hold_todo counts how many of its
    -- leading bytes are still meaningless, i.e. how many bytes the
    -- packet still owes before any byte may be emitted.
    skip_beat: natural range 0 to skip_beat_count_c+1;
    hold: byte_string(0 to fcs_size_c-1);
    hold_todo: natural range 0 to fcs_size_c;

    trim_valid: boolean;
    -- Whether the beat carries any byte at all: the leading beats of a
    -- packet are entirely withheld.
    trim_push: boolean;
    trim_bytes: beat_bytes_t;
    trim_keep: beat_keep_t;
    trim_last: boolean;
    trim_reject: boolean;
    trim_covered: natural range 0 to width_c;
    trim_covered_bytes: beat_bytes_t;

    -- Fold stage.  Only the comparison against the minimum frame size
    -- matters, so the size is counted down to zero and saturates there.
    fcs: crc_state_t;
    size_todo: natural range 0 to min_frame_size_c;

    check_valid: boolean;
    check_bytes: beat_bytes_t;
    check_keep: beat_keep_t;
    check_last: boolean;
    check_reject: boolean;
    check_fcs: crc_state_t;
    check_size_todo: natural range 0 to min_frame_size_c;

    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

  -- Skipped bytes of the beat the given beat index carries, i.e. the
  -- bytes preceding the first ethernet header byte.  A decode of one
  -- register.
  function skip_bytes(beat: natural) return natural
  is
  begin
    if beat < skip_beat_count_c then
      return width_c;
    elsif beat = skip_beat_count_c then
      return skip_byte_count_c;
    else
      return 0;
    end if;
  end function;

  -- Kept bytes of the beat the FCS covers.  Beats are packed, so this
  -- is a gated population count over the keep field, which is at most
  -- four bits wide.
  function covered_count(k: std_ulogic_vector;
                         skip: natural) return natural
  is
    alias kk: std_ulogic_vector(0 to k'length-1) is k;
    variable ret: natural := 0;
  begin
    for i in kk'range
    loop
      if kk(i) = '1' and i >= skip then
        ret := ret + 1;
      end if;
    end loop;
    return ret;
  end function;

  -- The length bytes of data starting at offset.  One mux per output
  -- byte, all sharing the same select.
  function byte_window(data: byte_string;
                       offset: natural;
                       length: natural) return byte_string
  is
    alias d: byte_string(0 to data'length-1) is data;
    variable ret: byte_string(0 to length-1) := (others => dontcare_byte_c);
  begin
    for i in ret'range
    loop
      if offset + i <= d'high then
        ret(i) := d(offset + i);
      end if;
    end loop;
    return ret;
  end function;

  -- Keep field of a packed beat carrying count bytes.
  function keep_mask(count: natural) return std_ulogic_vector
  is
    variable ret: beat_keep_t;
  begin
    for i in ret'range
    loop
      ret(i) := to_logic(i < count);
    end loop;
    return ret;
  end function;

  -- Folding the FCS bytes along with the frame yields a constant
  -- residue, which spares locating the FCS in the stream.
  --
  -- Every candidate count starts from the same state, so the count
  -- selects among parallel networks instead of gating a chain of them.
  function fcs_fold(state: crc_state_t;
                    data: byte_string;
                    count: natural) return crc_state_t
  is
    alias d: byte_string(0 to data'length-1) is data;
    variable ret: crc_state_t := state;
  begin
    for i in 1 to d'length
    loop
      if i = count then
        ret := crc_update(fcs_params_c, state, d(0 to i-1));
      end if;
    end loop;
    return ret;
  end function;

  -- Subtraction saturating at zero: one subtractor, and the comparison
  -- selecting the result takes the same two operands.
  function sub_sat(value: natural; delta: natural) return natural
  is
  begin
    if value > delta then
      return value - delta;
    end if;
    return 0;
  end function;

  -- User field carrying the reject flag defined by nsl_inet.stream.
  function reject_user(rejected: boolean) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(config_c.user_width-1 downto 0)
      := (others => '0');
  begin
    ret(0) := to_logic(rejected);
    return ret;
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
  assert config_c.has_keep
    report "Configuration must have keep signals"
    severity failure;
  assert config_c.user_width >= 1
    report "Configuration must have a user bit for the reject flag"
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
      r.skip_beat <= 0;
      r.hold_todo <= fcs_size_c;
      r.trim_valid <= false;
      r.fcs <= crc_init(fcs_params_c);
      r.size_todo <= min_frame_size_c;
      r.check_valid <= false;
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable push_v, pop_v: boolean;
    variable check_free_v, trim_free_v, trim_take_v, in_take_v: boolean;
    variable rejected_v: boolean;
    variable beat_v: master_t;
    variable fcs_v: crc_state_t;
    variable size_todo_v: natural range 0 to min_frame_size_c;
    variable skip_v: natural range 0 to width_c;
    variable in_count_v: natural range 0 to width_c;
    variable covered_v: natural range 0 to width_c;
    variable covered_bytes_v: beat_bytes_t;
    variable window_v: window_t;
    variable emit_v: natural range 0 to width_c;
    variable hold_todo_v: natural range 0 to fcs_size_c;
  begin
    rin <= r;

    -- Handshake.  Each stage takes the beat the previous one holds as
    -- soon as its own output slot is free, and the fifo takes the last
    -- one.  Every term is a register, so the whole handshake is one
    -- cone over the two stage flags and the fifo fillness, and none of
    -- the data paths below waits on it.
    pop_v := r.fifo_fillness > 0 and is_ready(config_c, out_i);
    push_v := r.check_valid and r.fifo_fillness < fifo_depth_c;
    check_free_v := not r.check_valid or r.fifo_fillness < fifo_depth_c;
    trim_free_v := not r.trim_valid or check_free_v;
    trim_take_v := r.trim_valid and check_free_v;
    in_take_v := is_valid(config_c, in_i) and trim_free_v;

    -- Check stage.  Every term of the verdict is a register, so the
    -- fold and the residue check sit in different cycles.  The flag
    -- only means anything on the last beat of a packet.
    rejected_v := r.check_reject
                  or r.check_size_todo /= 0
                  or not crc_is_valid(fcs_params_c, r.check_fcs);

    beat_v := transfer(config_c,
                       bytes => r.check_bytes,
                       keep => r.check_keep,
                       user => reject_user(r.check_last and rejected_v),
                       valid => true,
                       last => r.check_last);

    if push_v then
      rin.check_valid <= false;
    end if;

    -- Fold stage.  Its inputs are registers only, so the fold network
    -- starts at a flip-flop.
    fcs_v := fcs_fold(r.fcs, r.trim_covered_bytes, r.trim_covered);
    size_todo_v := sub_sat(r.size_todo, r.trim_covered);

    if trim_take_v then
      rin.trim_valid <= false;

      rin.check_valid <= r.trim_push;
      rin.check_bytes <= r.trim_bytes;
      rin.check_keep <= r.trim_keep;
      rin.check_last <= r.trim_last;
      rin.check_reject <= r.trim_reject;
      rin.check_fcs <= fcs_v;
      rin.check_size_todo <= size_todo_v;

      if r.trim_last then
        rin.fcs <= crc_init(fcs_params_c);
        rin.size_todo <= min_frame_size_c;
      else
        rin.fcs <= fcs_v;
        rin.size_todo <= size_todo_v;
      end if;
    end if;

    -- Trim stage.  The window holds the bytes seen so far that may
    -- still turn out to be the FCS, followed by the ones the beat
    -- brings.  Whatever leaves the window is proven not to be the FCS
    -- and is emitted; the trailing fcs_size_c bytes stay.
    --
    -- The emitted count and the count of bytes still owed are two
    -- subtractions of the same two operands, so neither waits on the
    -- other.
    skip_v := skip_bytes(r.skip_beat);
    in_count_v := byte_count(config_c, in_i);
    covered_v := covered_count(keep(config_c, in_i), skip_v);
    covered_bytes_v := byte_window(bytes(config_c, in_i), skip_v, width_c);
    window_v := r.hold & bytes(config_c, in_i);
    emit_v := sub_sat(in_count_v, r.hold_todo);
    hold_todo_v := sub_sat(r.hold_todo, in_count_v);

    if in_take_v then
      rin.trim_valid <= true;
      rin.trim_push <= in_count_v > r.hold_todo;
      rin.trim_bytes <= byte_window(window_v, r.hold_todo, width_c);
      rin.trim_keep <= keep_mask(emit_v);
      rin.trim_last <= is_last(config_c, in_i);
      rin.trim_reject <= is_rejected(config_c, in_i);
      rin.trim_covered <= covered_v;
      rin.trim_covered_bytes <= covered_bytes_v;

      if is_last(config_c, in_i) then
        rin.hold_todo <= fcs_size_c;
        rin.skip_beat <= 0;
      else
        rin.hold <= byte_window(window_v, in_count_v, fcs_size_c);
        rin.hold_todo <= hold_todo_v;
        if r.skip_beat <= skip_beat_count_c then
          rin.skip_beat <= r.skip_beat + 1;
        end if;
      end if;
    end if;

    rin.fifo <= fifo_shift_data(r.fifo, r.fifo_fillness,
                                push_v, beat_v, pop_v);
    rin.fifo_fillness <= fifo_shift_fillness(r.fifo_fillness, fifo_depth_c,
                                             push_v, pop_v);
  end process;

  moore: process(r) is
  begin
    -- Input ready deasserts only when both pipeline slots are taken
    -- and the fifo is full, i.e. only as a consequence of backpressure
    -- on the output side.
    in_o <= accept(config_c,
                   not r.trim_valid
                   or not r.check_valid
                   or r.fifo_fillness < fifo_depth_c);

    if r.fifo_fillness > 0 then
      out_o <= r.fifo(0);
    else
      out_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
