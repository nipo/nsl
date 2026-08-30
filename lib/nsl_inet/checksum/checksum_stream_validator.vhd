library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_inet.stream.all;
use work.checksum.all;

entity checksum_stream_validator is
  generic(
    config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    init_i : in checksum_state_t := checksum_init(checksum_config(config_c));

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of checksum_stream_validator is

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c: integer := 2;

  -- One beat is folded per cycle, whatever the stream width.
  constant checksum_c: checksum_config_t := checksum_config(config_c);

  -- Accumulator a beat folds into: the running one inside a packet,
  -- the seed at its first beat.  Both are available before the fold,
  -- so this is a select ahead of the adder rather than a step of its
  -- own.
  function fold_base(in_packet: boolean;
                     running, seed: checksum_state_t)
    return checksum_state_t
  is
  begin
    if in_packet then
      return running;
    end if;

    return seed;
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
    checksum: checksum_state_t;
    in_packet: boolean;
    -- Beat whose contribution is already registered, with the
    -- accumulator it left.  Folding a beat and reducing the outcome
    -- to a verdict would put two adders and a comparison in one
    -- cycle; held here, the fold is one adder between two registers
    -- and the verdict keeps the reduction alone.
    pending: master_t;
    pending_valid: boolean;
    pending_sum: checksum_state_t;
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

  assert config_c.has_last
    report "Configuration must have last signal"
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
      r.in_packet <= false;
      r.checksum <= checksum_init(checksum_c);
      r.pending_valid <= false;
      r.pending_sum <= checksum_init(checksum_c);
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i, init_i) is
    variable push_v, drain_v, pop_v, last_v, valid_v: boolean;
    variable checksum_v: checksum_state_t;
    variable entry_v: master_t;
  begin
    rin <= r;

    drain_v := r.pending_valid and r.fifo_fillness < fifo_depth_c;
    push_v := is_valid(config_c, in_i) and (not r.pending_valid or drain_v);
    pop_v := r.fifo_fillness > 0 and is_ready(config_c, out_i);
    last_v := is_last(config_c, in_i);

    -- init_i is sampled on the first beat of a packet; it holds the
    -- accumulator the pseudo-header of UDP/TCP leaves.
    checksum_v := checksum_update(checksum_c,
                                  fold_base(r.in_packet, r.checksum, init_i),
                                  config_c, in_i);

    -- Verdict of the beat held in the pipeline stage, its own
    -- contribution already registered.
    valid_v := checksum_is_valid(checksum_c, r.pending_sum);
    entry_v := verdict_apply(r.pending,
                             is_rejected(config_c, r.pending)
                             or not valid_v);

    if push_v then
      rin.pending <= in_i;
      rin.pending_valid <= true;
      rin.pending_sum <= checksum_v;

      if last_v then
        rin.in_packet <= false;
        rin.checksum <= checksum_init(checksum_c);
      else
        rin.in_packet <= true;
        rin.checksum <= checksum_v;
      end if;
    elsif drain_v then
      rin.pending_valid <= false;
    end if;

    rin.fifo <= fifo_shift_data(r.fifo, r.fifo_fillness,
                                drain_v, entry_v, pop_v);
    rin.fifo_fillness <= fifo_shift_fillness(r.fifo_fillness, fifo_depth_c,
                                             drain_v, pop_v);
  end process;

  moore: process(r) is
  begin
    in_o <= accept(config_c,
                   not r.pending_valid or r.fifo_fillness < fifo_depth_c);

    if r.fifo_fillness > 0 then
      out_o <= r.fifo(0);
    else
      out_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
