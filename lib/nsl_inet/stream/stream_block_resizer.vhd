library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.stream.all;

entity stream_block_resizer is
  generic(
    in_config_c : config_t;
    out_config_c : config_t;
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

architecture beh of stream_block_resizer is

  constant in_width_c : natural := in_config_c.data_width;
  constant out_width_c : natural := out_config_c.data_width;
  constant block_count_c : natural := header_length_c'length;
  -- Block descriptors are indexed by a register whose subtype must
  -- exist even when there is no block at all, hence the dummy entry.
  constant table_size_c : natural := nsl_math.arith.max(block_count_c, 1);

  function length_table(lengths: integer_vector) return integer_vector
  is
    variable ret: integer_vector(0 to table_size_c-1) := (others => 1);
  begin
    for i in 0 to lengths'length-1
    loop
      ret(i) := lengths(lengths'left + i);
    end loop;
    return ret;
  end function;

  function pad_table(lengths: integer_vector;
                     width: natural) return integer_vector
  is
    variable ret: integer_vector(0 to table_size_c-1) := (others => 0);
    variable len: integer;
  begin
    for i in 0 to lengths'length-1
    loop
      len := lengths(lengths'left + i);
      ret(i) := ((len + width - 1) / width) * width - len;
    end loop;
    return ret;
  end function;

  constant content_len_c : integer_vector(0 to table_size_c-1)
    := length_table(header_length_c);
  constant in_pad_c : integer_vector(0 to table_size_c-1)
    := pad_table(header_length_c, in_width_c);
  constant out_pad_c : integer_vector(0 to table_size_c-1)
    := pad_table(header_length_c, out_width_c);

  constant to_go_max_c : natural
    := nsl_math.arith.max(max(content_len_c, 0),
                          nsl_math.arith.max(max(in_pad_c, 0),
                                             max(out_pad_c, 0)));

  type state_t is (
    -- Forwarding the contents of block block_idx
    ST_CONTENT,
    -- Generating the output-side padding of block block_idx
    ST_OUT_PAD,
    -- Dropping the input-side padding of block block_idx
    ST_IN_PAD,
    -- Forwarding the payload until the input packet ends
    ST_PAYLOAD
    );

  function initial_state return state_t
  is
  begin
    if block_count_c = 0 then
      return ST_PAYLOAD;
    else
      return ST_CONTENT;
    end if;
  end function;

  function initial_to_go return natural
  is
  begin
    if block_count_c = 0 then
      return 0;
    else
      return content_len_c(0);
    end if;
  end function;

  -- Input beats are held byte-addressable, so only what a byte-serial
  -- engine needs of them is kept.
  type slot_t is
  record
    data: byte_string(0 to in_width_c-1);
    count: natural range 0 to in_width_c;
    last: boolean;
    rejected: boolean;
  end record;

  type slot_vector is array (natural range <>) of slot_t;

  -- Two slots let the input side accept a beat every cycle while its
  -- ready is a register.
  constant slot_count_c : natural := 2;

  type regs_t is
  record
    slot: slot_vector(0 to slot_count_c-1);
    fillness: natural range 0 to slot_count_c;
    idx: natural range 0 to in_width_c-1;

    state: state_t;
    block_idx: natural range 0 to table_size_c-1;
    to_go: natural range 0 to to_go_max_c;
    -- Last byte of the input packet has been consumed, its reject flag
    -- is captured.
    ended: boolean;
    rejected: boolean;

    -- Output beat under construction.  A complete one is only handed
    -- over once another byte shows up, so that the packet's last beat
    -- is still available for its last flag when the packet ends.
    acc: byte_string(0 to out_width_c-1);
    acc_count: natural range 0 to out_width_c;
    out_beat: master_t;
    out_valid: boolean;
  end record;

  signal r, rin: regs_t;

  function to_slot(m: master_t) return slot_t
  is
    variable ret: slot_t;
  begin
    ret.data := bytes(in_config_c, m);
    ret.count := byte_count(in_config_c, m);
    ret.last := is_last(in_config_c, m);
    ret.rejected := is_rejected(in_config_c, m);
    return ret;
  end function;

  function count_keep(count: natural) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to out_width_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_logic(i < count);
    end loop;
    return ret;
  end function;

  -- Increment wrapping to zero at the end of the range.  A bare
  -- r.x + 1 on a register whose range holds a single value folds to
  -- a constant out of that range, which synthesis rejects even when
  -- the branch is unreachable.
  function wrap_next(idx, count: natural) return natural
  is
  begin
    if idx + 1 >= count then
      return 0;
    end if;
    return idx + 1;
  end function;

  function zero_padded(data: byte_string; count: natural) return byte_string
  is
    variable ret: byte_string(0 to out_width_c-1) := (others => x"00");
  begin
    for i in ret'range
    loop
      if i < count then
        ret(i) := data(data'left + i);
      end if;
    end loop;
    return ret;
  end function;

begin

  assert in_config_c.has_last and out_config_c.has_last
    report "Both configurations must have a last signal"
    severity failure;
  assert in_config_c.has_keep and out_config_c.has_keep
    report "Both configurations must have keep signals"
    severity failure;
  assert in_config_c.user_width >= 1 and out_config_c.user_width >= 1
    report "Both configurations must have a user bit for the reject flag"
    severity failure;

  monitor: process(clock_i) is
  begin
    if rising_edge(clock_i) and reset_n_i = '1' then
      if is_valid(in_config_c, in_i) then
        assert is_packed(in_config_c, in_i)
          report "Sparse keep pattern, not supported"
          severity failure;
        assert byte_count(in_config_c, in_i) /= 0
          report "Empty beat, not supported"
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
      r.fillness <= 0;
      r.idx <= 0;
      r.state <= initial_state;
      r.block_idx <= 0;
      r.to_go <= initial_to_go;
      r.ended <= false;
      r.rejected <= false;
      r.acc_count <= 0;
      r.out_valid <= false;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable in_avail_v, slot_end_v, packet_end_v: boolean;
    variable in_byte_v: byte;
    variable out_free_v, can_push_v: boolean;
    variable push_v, consume_v, finish_v, truncate_v: boolean;
    variable push_byte_v: byte;
    variable load_v, pop_v: boolean;
    variable slot_idx_v: natural;
  begin
    rin <= r;

    in_avail_v := r.fillness /= 0;
    in_byte_v := r.slot(0).data(r.idx);
    slot_end_v := r.idx + 1 = r.slot(0).count;
    packet_end_v := slot_end_v and r.slot(0).last;

    out_free_v := not r.out_valid or is_ready(out_config_c, out_i);
    can_push_v := r.acc_count /= out_width_c or out_free_v;

    push_v := false;
    push_byte_v := x"00";
    consume_v := false;
    finish_v := false;
    truncate_v := false;

    case r.state is
      when ST_CONTENT =>
        if r.ended then
          truncate_v := true;
          finish_v := out_free_v;
        elsif in_avail_v and can_push_v then
          consume_v := true;
          push_v := true;
          push_byte_v := in_byte_v;

          if r.to_go = 1 then
            rin.state <= ST_OUT_PAD;
            rin.to_go <= out_pad_c(r.block_idx);
          else
            rin.to_go <= r.to_go - 1;
          end if;
        end if;

      when ST_OUT_PAD =>
        if r.to_go = 0 then
          rin.state <= ST_IN_PAD;
          rin.to_go <= in_pad_c(r.block_idx);
        elsif can_push_v then
          push_v := true;
          rin.to_go <= r.to_go - 1;
        end if;

      when ST_IN_PAD =>
        if r.to_go = 0 then
          if r.block_idx = block_count_c - 1 then
            rin.state <= ST_PAYLOAD;
          else
            rin.state <= ST_CONTENT;
            rin.block_idx <= wrap_next(r.block_idx, table_size_c);
            rin.to_go <= content_len_c(wrap_next(r.block_idx, table_size_c));
          end if;
        elsif r.ended then
          truncate_v := true;
          finish_v := out_free_v;
        elsif in_avail_v then
          consume_v := true;
          rin.to_go <= r.to_go - 1;
        end if;

      when ST_PAYLOAD =>
        if r.ended then
          finish_v := out_free_v;
        elsif in_avail_v and can_push_v then
          consume_v := true;
          push_v := true;
          push_byte_v := in_byte_v;
        end if;
    end case;

    assert not finish_v or r.acc_count /= 0
      report "Closing an output packet that carries no byte"
      severity failure;

    load_v := r.fillness /= slot_count_c and is_valid(in_config_c, in_i);
    pop_v := consume_v and slot_end_v;
    slot_idx_v := r.fillness - if_else(pop_v, 1, 0);

    if consume_v then
      if slot_end_v then
        rin.idx <= 0;
      else
        rin.idx <= wrap_next(r.idx, in_width_c);
      end if;

      if packet_end_v then
        rin.ended <= true;
        rin.rejected <= r.slot(0).rejected;
      end if;
    end if;

    if pop_v then
      rin.slot(0) <= r.slot(1);
    end if;

    if load_v then
      rin.slot(slot_idx_v) <= to_slot(in_i);
    end if;

    if load_v and not pop_v then
      rin.fillness <= r.fillness + 1;
    elsif pop_v and not load_v then
      rin.fillness <= r.fillness - 1;
    end if;

    if out_free_v then
      rin.out_valid <= false;
    end if;

    if finish_v then
      rin.out_beat <= reject_set(out_config_c,
                                 transfer(out_config_c,
                                          bytes => zero_padded(r.acc,
                                                               r.acc_count),
                                          keep => count_keep(r.acc_count),
                                          user => "0",
                                          valid => true,
                                          last => true),
                                 r.rejected or truncate_v);
      rin.out_valid <= true;
      rin.acc_count <= 0;
      rin.ended <= false;
      rin.rejected <= false;
      rin.state <= initial_state;
      rin.block_idx <= 0;
      rin.to_go <= initial_to_go;
    elsif push_v then
      if r.acc_count = out_width_c then
        rin.out_beat <= transfer(out_config_c,
                                 bytes => r.acc,
                                 user => "0",
                                 valid => true,
                                 last => false);
        rin.out_valid <= true;
        rin.acc(0) <= push_byte_v;
        rin.acc_count <= 1;
      else
        rin.acc(r.acc_count) <= push_byte_v;
        rin.acc_count <= r.acc_count + 1;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    in_o <= accept(in_config_c, r.fillness /= slot_count_c);

    if r.out_valid then
      out_o <= r.out_beat;
    else
      out_o <= transfer_defaults(out_config_c);
    end if;
  end process;

end architecture;
