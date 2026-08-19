library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

-- Pipeline:
--   Stages 1 .. data_width-1: one bubble-collapse pass each, moving
--     every enabled lane one step down when the lane below is free.
--     After data_width-1 passes, enabled lanes are contiguous at the
--     bottom of the vector.  There is no such stage for data_width=1.
--   Stage data_width: alignment.  The compacted vector is shifted up
--     by the running count of bytes left over in the merge buffer, and
--     an emit flag is computed for the beat.
--   Stage data_width+1: merge.  The aligned vector is merged in the
--     buffer; on emit, the low data_width lanes are moved to the
--     output register and the buffer is shifted down by data_width.
--
-- Latency: data_width+1 cycles.  Buffer size: 2*data_width-1 lanes.
entity axi4_stream_packer is
  generic(
    config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
begin

  assert config_c.has_strobe
    report "has_strobe must be set, lane gaps are expressed through strobe"
    severity failure;

  assert not config_c.has_last
    report "has_last must be cleared, bytes of different beats get merged"
    severity failure;

  assert not config_c.has_keep
    report "has_keep must be cleared, bytes of different beats get merged"
    severity failure;

  assert config_c.id_width = 0
    report "id_width must be zero, bytes of different beats get merged"
    severity failure;

  assert config_c.dest_width = 0
    report "dest_width must be zero, bytes of different beats get merged"
    severity failure;

  assert config_c.user_width mod config_c.data_width = 0
    report "user_width must be a multiple of data_width"
    severity failure;

end entity;

architecture beh of axi4_stream_packer is

  constant data_width_c: positive := config_c.data_width;
  constant user_per_byte_c: natural := config_c.user_width / data_width_c;
  -- Highest index of the merge buffer.  A beat can be aligned up to
  -- data_width-1 lanes above the bottom, hence the extra room.
  constant buffer_top_c: natural := 2 * data_width_c - 2;

  subtype lane_count_t is integer range 0 to data_width_c;

  type lane_t is
  record
    data: byte;
    user: std_ulogic_vector(user_per_byte_c-1 downto 0);
    en: std_ulogic;
  end record;

  type lane_vector is array (integer range <>) of lane_t;

  subtype beat_lanes_t is lane_vector(0 to data_width_c-1);
  subtype buffer_lanes_t is lane_vector(0 to buffer_top_c);
  type beat_lanes_vector is array (integer range <>) of beat_lanes_t;

  constant lane_none_c: lane_t := (
    data => (others => '-'),
    user => (others => '-'),
    en => '0'
    );

  -- Spread an input beat over lanes.  A lane is enabled only if the
  -- beat is valid and its strobe bit is set.
  function to_lanes(m: master_t) return beat_lanes_t
  is
    constant b: byte_string(0 to data_width_c-1) := bytes(config_c, m);
    constant s: std_ulogic_vector(0 to data_width_c-1) := strobe(config_c, m);
    constant u: std_ulogic_vector(config_c.user_width-1 downto 0) := user(config_c, m);
    constant valid: std_ulogic := to_logic(is_valid(config_c, m));
    variable ret: beat_lanes_t;
  begin
    for i in ret'range
    loop
      ret(i).data := b(i);
      ret(i).user := u((i+1)*user_per_byte_c-1 downto i*user_per_byte_c);
      ret(i).en := s(i) and valid;
    end loop;
    return ret;
  end function;

  function to_master(l: beat_lanes_t; valid: boolean) return master_t
  is
    variable b: byte_string(0 to data_width_c-1);
    variable u: std_ulogic_vector(config_c.user_width-1 downto 0);
  begin
    for i in l'range
    loop
      assert not valid or l(i).en = '1'
        report "Emitting a beat with an unfilled lane"
        severity failure;

      b(i) := l(i).data;
      u((i+1)*user_per_byte_c-1 downto i*user_per_byte_c) := l(i).user;
    end loop;
    return transfer(config_c,
                    bytes => b,
                    user => u,
                    valid => valid);
  end function;

  -- One bubble-collapse pass.  data_width-1 passes fully compact a
  -- beat: the highest enabled lane has at most data_width-1 free lanes
  -- below it and gets one step closer to its final position on every
  -- pass.  Both rules writing ret(i) cannot apply at once, they
  -- require opposite values of l(i).en.
  function compacted(l: beat_lanes_t) return beat_lanes_t
  is
    variable ret: beat_lanes_t := l;
  begin
    for i in 0 to data_width_c-2
    loop
      if l(i).en = '0' and l(i+1).en = '1' then
        ret(i) := l(i+1);
        ret(i+1).en := '0';
      end if;
    end loop;
    return ret;
  end function;

  -- count must not exceed data_width-1 for the result to fit.
  function shifted_up(l: beat_lanes_t; count: natural) return buffer_lanes_t
  is
    variable ret: buffer_lanes_t := (others => lane_none_c);
  begin
    for i in l'range
    loop
      ret(i + count) := l(i);
    end loop;
    return ret;
  end function;

  -- Drop the data_width lanes that just left in an output beat.
  function shifted_down(b: buffer_lanes_t) return buffer_lanes_t
  is
    variable ret: buffer_lanes_t := (others => lane_none_c);
  begin
    for i in 0 to buffer_top_c - data_width_c
    loop
      ret(i) := b(i + data_width_c);
    end loop;
    return ret;
  end function;

  -- Both arguments are expected to have disjoint enabled lanes.
  function merged(buf, add: buffer_lanes_t) return buffer_lanes_t
  is
    variable ret: buffer_lanes_t := buf;
  begin
    for i in ret'range
    loop
      if add(i).en = '1' then
        ret(i) := add(i);
      end if;
    end loop;
    return ret;
  end function;

  function enabled_count(l: beat_lanes_t) return lane_count_t
  is
    variable ret: lane_count_t := 0;
  begin
    for i in l'range
    loop
      if l(i).en = '1' then
        ret := ret + 1;
      end if;
    end loop;
    return ret;
  end function;

  function pipeline_enabled(out_valid: std_ulogic; s: slave_t) return boolean
  is
  begin
    return out_valid = '0' or is_ready(config_c, s);
  end function;

  type regs_t is
  record
    -- Compaction stages, index 0 is fed by the input.
    comp: beat_lanes_vector(0 to data_width_c-2);
    -- Alignment stage
    align: buffer_lanes_t;
    align_emit: std_ulogic;
    -- Occupancy the merge stage will see when the beat currently in
    -- the alignment stage reaches it: every beat that already passed
    -- alignment is counted, including emits that have been decided
    -- but not yet performed.  This lets the alignment stage place its
    -- beat one cycle ahead of the merge, and only holds because
    -- alignment and merge are exactly one stage apart and share the
    -- pipeline enable.
    fill: integer range 0 to data_width_c-1;
    -- Merge stage
    buf: buffer_lanes_t;
    -- Output register
    out_lanes: beat_lanes_t;
    out_valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      for stage in r.comp'range
      loop
        for i in beat_lanes_t'range
        loop
          r.comp(stage)(i).en <= '0';
        end loop;
      end loop;
      for i in buffer_lanes_t'range
      loop
        r.align(i).en <= '0';
        r.buf(i).en <= '0';
      end loop;
      r.align_emit <= '0';
      r.fill <= 0;
      r.out_valid <= '0';
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable comp_v: beat_lanes_vector(0 to data_width_c-2);
    variable align_in: beat_lanes_t;
    variable count: lane_count_t;
    variable fill_after: natural range 0 to 2*data_width_c-1;
    variable merged_v: buffer_lanes_t;
  begin
    rin <= r;

    -- Variables are computed whether the pipeline moves or not, so
    -- synthesis does not put latch enables on them.
    --
    -- align_in ends up holding the fully compacted beat entering the
    -- alignment stage, which is the input beat itself when there is
    -- no compaction stage at all.
    align_in := to_lanes(in_i);
    for stage in comp_v'range
    loop
      comp_v(stage) := compacted(align_in);
      align_in := r.comp(stage);
    end loop;
    count := enabled_count(align_in);
    fill_after := r.fill + count;
    merged_v := merged(r.buf, r.align);

    if pipeline_enabled(r.out_valid, out_i) then
      -- Compaction stages.
      rin.comp <= comp_v;

      -- Alignment stage.
      rin.align <= shifted_up(align_in, r.fill);
      if fill_after >= data_width_c then
        rin.align_emit <= '1';
        rin.fill <= fill_after - data_width_c;
      else
        rin.align_emit <= '0';
        rin.fill <= fill_after;
      end if;

      -- Merge stage.
      if r.align_emit = '1' then
        rin.out_lanes <= merged_v(0 to data_width_c-1);
        rin.buf <= shifted_down(merged_v);
        rin.out_valid <= '1';
      else
        rin.buf <= merged_v;
        rin.out_valid <= '0';
      end if;
    end if;
  end process;

  outputs: process(r, out_i) is
  begin
    in_o <= accept(config_c, pipeline_enabled(r.out_valid, out_i));
    out_o <= to_master(r.out_lanes, r.out_valid = '1');
  end process;

end architecture;
