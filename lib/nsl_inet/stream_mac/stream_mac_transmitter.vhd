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

entity stream_mac_transmitter is
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

architecture beh of stream_mac_transmitter is

  constant width_c: natural := config_c.data_width;
  constant fcs_size_c: natural := crc_byte_length(fcs_params_c);
  constant min_frame_size_c: natural := 64;
  constant padded_size_c: natural := min_frame_size_c - fcs_size_c;

  -- Bytes preceding the first ethernet header byte: the forwarded
  -- blocks, then the front pad of the frame block.
  constant skip_size_c: natural := context_byte_count(config_c, header_length_c)
                                   + ethernet_frame_offset(config_c);
  -- Beats fully covered by the skipped bytes, then the skipped bytes
  -- remaining in the beat that starts the ethernet header.
  constant skip_beat_count_c: natural := skip_size_c / width_c;
  constant skip_byte_count_c: natural := skip_size_c mod width_c;

  -- Padding fills the last frame beat, then whole beats until the
  -- minimum size is reached.  Frames therefore reach the wire up to
  -- width-1 bytes longer than the minimum size alone would ask for;
  -- the extra bytes take part in the FCS, and receivers trim them
  -- from the length field of the protocol above, exactly like the
  -- padding the minimum frame size mandates.
  --
  -- In exchange, every fold takes a whole word and the FCS spans
  -- whole beats.
  constant pad_beat_count_c: natural := (padded_size_c + width_c - 1) / width_c;
  constant fcs_beat_count_c: natural := fcs_size_c / width_c;

  -- The bytes still missing before the frame reaches the minimum size
  -- are counted with a bias of one byte less than a whole beat.  The
  -- whole padding beats they amount to are then the high bits of the
  -- counter, so the rounding costs no adder behind the subtraction.
  constant pad_bias_c: natural := width_c - 1;
  constant pad_slack_init_c: natural := padded_size_c + pad_bias_c;

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c: natural := 2;

  constant pad_bytes_c: byte_string(0 to width_c-1) := (others => x"00");

  subtype beat_bytes_t is byte_string(0 to width_c-1);
  subtype beat_keep_t is std_ulogic_vector(0 to width_c-1);

  type state_t is (
    ST_FORWARD,
    ST_PAD,
    ST_FCS
    );

  type regs_t is
  record
    -- Ingress stage: state of the FCS over the bytes covered so far,
    -- and the accounting that goes with it.
    fcs: crc_state_t;
    pad_slack: natural range 0 to pad_slack_init_c;
    skip_beat: natural range 0 to skip_beat_count_c+1;

    -- Beat handed over to the tail stage, padding included, with the
    -- FCS state and the whole-beat padding count that follow it.  The
    -- tail stage builds its beat from these registers only.
    beat_valid: boolean;
    beat_data: beat_bytes_t;
    beat_last: boolean;
    beat_corrupt: boolean;
    beat_fcs: crc_state_t;
    beat_pad: natural range 0 to pad_beat_count_c;

    -- Tail stage: what the frame still owes once the inbound beats
    -- are exhausted.
    state: state_t;
    tail_fcs: crc_state_t;
    pad_left: natural range 0 to pad_beat_count_c;
    fcs_left: natural range 0 to fcs_beat_count_c;
    corrupt: boolean;

    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

  -- Skipped bytes of the beat the given beat index carries, i.e. the
  -- bytes preceding the first ethernet header byte, and the bytes the
  -- FCS covers in that same beat.  Two decodes of one register, so
  -- neither the slide nor the padding accounting waits on the other.
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

  function covered_bytes_count(beat: natural) return natural
  is
  begin
    if beat < skip_beat_count_c then
      return 0;
    elsif beat = skip_beat_count_c then
      return width_c - skip_byte_count_c;
    else
      return width_c;
    end if;
  end function;

  -- Frames are padded to a whole count of beats, so the bytes a
  -- partial last beat does not carry are padding.
  function keep_masked(data: byte_string;
                       k: std_ulogic_vector) return byte_string
  is
    alias d: byte_string(0 to data'length-1) is data;
    alias kk: std_ulogic_vector(0 to k'length-1) is k;
    variable ret: beat_bytes_t;
  begin
    for i in ret'range
    loop
      if kk(i) = '1' then
        ret(i) := d(i);
      else
        ret(i) := x"00";
      end if;
    end loop;
    return ret;
  end function;

  -- Bytes of a beat the FCS covers, slid to the start of the beat and
  -- padded where the beat carries nothing.  Masking and sliding share
  -- one mux, so the fold network is one level away from the input.
  function covered_beat(data: byte_string;
                        k: std_ulogic_vector;
                        skip: natural) return byte_string
  is
    alias d: byte_string(0 to data'length-1) is data;
    alias kk: std_ulogic_vector(0 to k'length-1) is k;
    variable ret: beat_bytes_t := (others => dontcare_byte_c);
  begin
    for i in ret'range
    loop
      if i + skip < width_c then
        if kk(i + skip) = '1' then
          ret(i) := d(i + skip);
        else
          ret(i) := x"00";
        end if;
      end if;
    end loop;
    return ret;
  end function;

  -- Every candidate count starts from the same state, so the count
  -- selects among parallel networks instead of gating a chain of them.
  -- As the last beat of a frame is filled with padding, the count only
  -- ever depends on the skipped prefix.
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

  -- Subtraction with a floor: one subtractor, and the comparison
  -- selecting the result takes the same two operands.
  function sub_floor(value: natural;
                     delta: natural;
                     floor: natural) return natural
  is
    variable diff: integer := value - delta;
  begin
    if diff > floor then
      return diff;
    end if;
    return floor;
  end function;

  -- FCS as it goes on the wire.  A frame arriving with the reject flag
  -- set gets a corrupted FCS, which is how a late cancellation reaches
  -- the peer.
  function fcs_output(state: crc_state_t;
                      corrupt: boolean) return byte_string
  is
  begin
    if corrupt then
      return not crc_spill(fcs_params_c, state);
    end if;
    return crc_spill(fcs_params_c, state);
  end function;

  -- The beat of the FCS the count of beats still owed designates.  A
  -- register selects among fixed slices.
  function fcs_beat(data: byte_string;
                    left: natural) return byte_string
  is
    alias d: byte_string(0 to data'length-1) is data;
    variable ret: beat_bytes_t := (others => dontcare_byte_c);
  begin
    for i in 1 to fcs_beat_count_c
    loop
      if i = left then
        ret := d(fcs_size_c - i*width_c
                 to fcs_size_c - i*width_c + width_c - 1);
      end if;
    end loop;
    return ret;
  end function;

  -- Bytes the tail stage puts on the wire.  Every one of them comes
  -- from a register, so the FCS is only rewired here, never folded.
  function tail_bytes(state: state_t;
                      forwarded: byte_string;
                      fcs_bytes: byte_string;
                      fcs_left: natural) return byte_string
  is
  begin
    case state is
      when ST_FORWARD =>
        return forwarded;

      when ST_PAD =>
        return pad_bytes_c;

      when ST_FCS =>
        return fcs_beat(fcs_bytes, fcs_left);
    end case;
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
  assert fcs_size_c mod width_c = 0
    report "Stream width must divide the FCS length"
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
      r.fcs <= crc_init(fcs_params_c);
      r.pad_slack <= pad_slack_init_c;
      r.skip_beat <= 0;
      r.beat_valid <= false;
      r.state <= ST_FORWARD;
      r.tail_fcs <= crc_init(fcs_params_c);
      r.fcs_left <= fcs_beat_count_c;
      r.pad_left <= 0;
      r.corrupt <= false;
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable push_v, pop_v, capture_v, consume_v, in_ready_v: boolean;
    variable filled_v, covered_bytes_v, data_v: beat_bytes_t;
    variable skip_v, covered_v: natural range 0 to width_c;
    variable fcs_v: crc_state_t;
    variable pad_slack_v: natural range 0 to pad_slack_init_c;
    variable fcs_bytes_v: byte_string(0 to fcs_size_c-1);
    variable keep_v: beat_keep_t;
    variable user_v: std_ulogic_vector(config_c.user_width-1 downto 0);
    variable beat_v: master_t;
  begin
    rin <= r;

    user_v := (others => '0');
    -- Every outgoing beat is full: padding tops up the last frame
    -- beat, and the padding and FCS beats that follow are whole.
    keep_v := (others => '1');
    pop_v := r.fifo_fillness > 0 and is_ready(config_c, out_i);

    -- Tail stage.
    push_v := r.fifo_fillness < fifo_depth_c
              and (r.beat_valid or r.state /= ST_FORWARD);
    consume_v := push_v and r.state = ST_FORWARD;

    fcs_bytes_v := fcs_output(r.tail_fcs, r.corrupt);
    data_v := tail_bytes(r.state, r.beat_data, fcs_bytes_v, r.fcs_left);

    beat_v := transfer(config_c,
                       bytes => data_v,
                       keep => keep_v,
                       user => user_v,
                       valid => true,
                       last => r.state = ST_FCS and r.fcs_left = 1);

    if push_v then
      case r.state is
        when ST_FORWARD =>
          if r.beat_last then
            rin.tail_fcs <= r.beat_fcs;
            rin.corrupt <= r.beat_corrupt;
            rin.pad_left <= r.beat_pad;
            rin.fcs_left <= fcs_beat_count_c;
            if r.beat_pad /= 0 then
              rin.state <= ST_PAD;
            else
              rin.state <= ST_FCS;
            end if;
          end if;

        when ST_PAD =>
          -- Padding takes part in the FCS, and whole beats of it fold
          -- through the same network as the frame data.
          rin.tail_fcs <= crc_update(fcs_params_c, r.tail_fcs, pad_bytes_c);
          rin.pad_left <= r.pad_left - 1;
          if r.pad_left = 1 then
            rin.state <= ST_FCS;
          end if;

        when ST_FCS =>
          rin.fcs_left <= r.fcs_left - 1;
          if r.fcs_left = 1 then
            rin.state <= ST_FORWARD;
            rin.tail_fcs <= crc_init(fcs_params_c);
            rin.corrupt <= false;
          end if;
      end case;
    end if;

    -- Ingress stage.  The beat is filled with the padding it owes and
    -- covered by the FCS here, so that the tail stage has whole beats
    -- of padding left at most.
    in_ready_v := not r.beat_valid or consume_v;

    skip_v := skip_bytes(r.skip_beat);
    covered_v := covered_bytes_count(r.skip_beat);
    filled_v := keep_masked(bytes(config_c, in_i), keep(config_c, in_i));
    covered_bytes_v := covered_beat(bytes(config_c, in_i),
                                    keep(config_c, in_i), skip_v);
    fcs_v := fcs_fold(r.fcs, covered_bytes_v, covered_v);
    pad_slack_v := sub_floor(r.pad_slack, covered_v, pad_bias_c);
    capture_v := is_valid(config_c, in_i) and in_ready_v;

    if capture_v then
      rin.beat_valid <= true;
      rin.beat_data <= filled_v;
      rin.beat_last <= is_last(config_c, in_i);
      rin.beat_corrupt <= is_rejected(config_c, in_i);
      rin.beat_fcs <= fcs_v;
      -- Dividing by the width is a wire slice: the bias put the whole
      -- padding beats owed in the high bits of the counter.
      rin.beat_pad <= pad_slack_v / width_c;

      if is_last(config_c, in_i) then
        rin.fcs <= crc_init(fcs_params_c);
        rin.pad_slack <= pad_slack_init_c;
        rin.skip_beat <= 0;
      else
        rin.fcs <= fcs_v;
        rin.pad_slack <= pad_slack_v;
        if r.skip_beat <= skip_beat_count_c then
          rin.skip_beat <= r.skip_beat + 1;
        end if;
      end if;
    elsif consume_v then
      rin.beat_valid <= false;
    end if;

    rin.fifo <= fifo_shift_data(r.fifo, r.fifo_fillness,
                                push_v, beat_v, pop_v);
    rin.fifo_fillness <= fifo_shift_fillness(r.fifo_fillness, fifo_depth_c,
                                             push_v, pop_v);
  end process;

  moore: process(r) is
  begin
    in_o <= accept(config_c,
                   not r.beat_valid
                   or (r.state = ST_FORWARD
                       and r.fifo_fillness < fifo_depth_c));

    if r.fifo_fillness > 0 then
      out_o <= r.fifo(0);
    else
      out_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
