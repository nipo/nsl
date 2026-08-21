library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_inet;
use nsl_inet.switching.all;

entity switching_fabric is
  generic(
    config_c: config_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    frame_i: in nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
    frame_o: out nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1);
    forward_i: in forward_req_vector(0 to config_c.port_count-1);
    forward_o: out forward_ack_vector(0 to config_c.port_count-1);

    out_o: out nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
    out_i: in nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1)
    );
end entity;

-- One FSM per egress port, all sharing a lock vector indexed by
-- ingress port. An egress port owning a lock has exclusive access to
-- the corresponding ingress read port for the duration of one frame
-- copy.
--
-- Arbitration is pipelined so that no egress port decision feeds
-- another one within a cycle:
--
--  * requests are turned into one "who wants me" vector per egress
--    port and registered, so the scan starts at a flip-flop,
--  * each egress port scans its own vector alone, ignoring the other
--    egress ports, and registers a candidate,
--  * the cycle after, candidates are confronted: an egress port wins
--    its candidate if the candidate is still requesting, still
--    unlocked and not claimed by a lower-numbered egress port. All the
--    terms of that decision are registered, so the P confrontations
--    happen in parallel rather than in a chain. Losers rescan.
--
-- Which egress port reads which ingress port is held as a registered
-- one-hot matrix, `reader`. Everything on the beat path selects
-- through it and nothing recomputes it: the ingress read data is
-- AND-OR muxed to the per-egress-port register slice, and the ready
-- coming back from that slice is AND-OR muxed to the ingress read
-- port. Both directions are then two levels of logic between two
-- registers. The matrix only changes on grant and on end of copy,
-- both of which are a cycle away from any beat.
--
-- Acknowledges are a registered one-hot matrix too, so forward_o
-- leaves the module straight out of a flip-flop.
--
-- Both stream boundaries are register slices, so nothing of the beat
-- path is shared with the neighbouring modules: frame_o(i).ready is
-- the input slice's own Moore ready with no fabric logic behind it,
-- out_o comes out of the output slice, and the whole mux sits between
-- two slices inside this module.
--
-- The input slices hold ingress beats, which needs the copy
-- accounting to hold across them:
--
--  * an ingress port streams exactly the words of the copy under way
--    and then stops until it is acknowledged, so within a copy no beat
--    can follow the last one,
--  * beats cross the input slice in order, and a copy is only
--    acknowledged once its last beat has been accepted by the output
--    slice, which is downstream of the input slice. The last beat has
--    therefore left the input slice by then, and, nothing following
--    it, the input slice is empty at every acknowledge,
--  * the ingress port only rewinds after seeing that acknowledge, so
--    the beats it pushes next are the first beats of the next copy,
--    behind an empty slice. No flush is ever needed, and no beat of a
--    finished copy can lead the next one.
--
-- The input slices accept beats whether or not the ingress port is
-- granted, which prefetches the head of the announced copy. That is
-- harmless for the same reason: those beats are the first beats of the
-- copy the ingress port currently announces, in order, and they are
-- exactly what the egress port that eventually wins the ingress port
-- has to consume first.
architecture beh of switching_fabric is

  constant port_count_c: natural := config_c.port_count;
  constant frame_config_c: nsl_amba.axi4_stream.config_t := internal_config(config_c);
  constant out_config_c: nsl_amba.axi4_stream.config_t := port_config(config_c);

  -- Beat items the ingress-to-egress mux has to carry.
  constant mux_elements_c: string := "dklv";
  constant mux_width_c: natural
    := nsl_amba.axi4_stream.vector_length(frame_config_c, mux_elements_c);

  subtype port_no_t is natural range 0 to port_count_c-1;
  subtype index_t is integer range -1 to port_count_c-1;
  subtype port_set_t is std_ulogic_vector(0 to port_count_c-1);
  type port_no_vector is array(natural range <>) of port_no_t;
  type index_vector is array(natural range <>) of index_t;
  type port_set_vector is array(natural range <>) of port_set_t;
  type flag_vector is array(natural range <>) of boolean;

  type state_t is (
    ST_RESET,
    -- Look for an ingress port to serve, alone
    ST_SCAN,
    -- Confront the candidate with the other egress ports
    ST_CLAIM,
    -- Stream one frame to the register slice
    ST_COPY,
    -- Pulse taken
    ST_ACK,
    -- Drop the lock, and let the request snapshot take the shrunk
    -- mask into account before scanning again
    ST_RELEASE
    );

  type state_vector is array(natural range <>) of state_t;

  type regs_t is
  record
    -- Registered requests, indexed by egress port: set of ingress
    -- ports whose head-of-queue frame still has to reach this egress
    -- port.
    want: port_set_vector(0 to port_count_c-1);

    -- Per egress port
    state: state_vector(0 to port_count_c-1);
    scan_start: port_no_vector(0 to port_count_c-1);
    candidate: port_no_vector(0 to port_count_c-1);
    source: port_no_vector(0 to port_count_c-1);

    -- Per ingress port
    locked: port_set_t;
    -- Egress port streaming an ingress port, one-hot, set on grant and
    -- cleared on the last beat. Indexed by ingress port; the transpose
    -- needed by the egress side is pure wiring.
    reader: port_set_vector(0 to port_count_c-1);
    -- Acknowledge matrix, indexed by ingress port. One-hot, high for
    -- exactly one cycle per completed copy.
    taken: port_set_vector(0 to port_count_c-1);
  end record;

  signal r, rin: regs_t;

  -- Ingress beat on the far side of the input slice, and the ready the
  -- reader logic hands back to it.
  signal in_beat_s: nsl_amba.axi4_stream.master_vector(0 to port_count_c-1);
  signal in_ack_s: nsl_amba.axi4_stream.slave_vector(0 to port_count_c-1);

  -- Ingress beat selected for one egress port, then the same on its
  -- way into the output slice, then the output slice acknowledge.
  signal read_beat_s, slice_in_s: nsl_amba.axi4_stream.master_vector(0 to port_count_c-1);
  signal slice_ack_s: nsl_amba.axi4_stream.slave_vector(0 to port_count_c-1);

  function wrap(index: natural) return port_no_t
  is
  begin
    if index >= port_count_c then
      return index - port_count_c;
    end if;
    return index;
  end function;

  function widen(v: port_set_t) return port_mask_t
  is
    variable ret: port_mask_t;
  begin
    ret := (others => '0');
    ret(0 to port_count_c-1) := v;

    return ret;
  end function;

  function any_set(v: port_set_t) return boolean
  is
    variable ret: boolean;
  begin
    ret := false;

    for index in v'range
    loop
      if v(index) = '1' then
        ret := true;
      end if;
    end loop;

    return ret;
  end function;

  -- Set of ingress ports asking for one egress port.
  function requesters(req: forward_req_vector;
                      egress: port_no_t) return port_set_t
  is
    variable ret: port_set_t;
  begin
    for ingress in 0 to port_count_c-1
    loop
      ret(ingress) := req(ingress).valid and req(ingress).mask(egress);
    end loop;

    return ret;
  end function;

  -- Ingress port an egress port should try next, or -1 when none of
  -- the requesters is available. Scan wraps around from start, which
  -- is what makes the arbitration round-robin.
  function candidate_of(want: port_set_t;
                        locked: port_set_t;
                        start: port_no_t) return index_t
  is
    variable ret: index_t;
  begin
    ret := -1;

    for offset in port_count_c-1 downto 0
    loop
      if want(wrap(start + offset)) = '1' and locked(wrap(start + offset)) = '0' then
        ret := wrap(start + offset);
      end if;
    end loop;

    return ret;
  end function;

  -- A claim wins when its candidate still asks for this egress port,
  -- is still unlocked, and is not claimed by a lower-numbered egress
  -- port in the same cycle.
  function claim_granted(r: regs_t;
                         egress: port_no_t) return boolean
  is
    variable ret: boolean;
  begin
    ret := r.want(egress)(r.candidate(egress)) = '1'
           and r.locked(r.candidate(egress)) = '0';

    for other in 0 to egress-1
    loop
      if r.state(other) = ST_CLAIM
        and r.candidate(other) = r.candidate(egress) then
        ret := false;
      end if;
    end loop;

    return ret;
  end function;

  -- Ingress port an egress port reads, one-hot, empty when it reads
  -- none. Transpose of the reader matrix, i.e. wires only.
  function read_by(r: regs_t;
                   egress: port_no_t) return port_set_t
  is
    variable ret: port_set_t;
  begin
    for ingress in 0 to port_count_c-1
    loop
      ret(ingress) := r.reader(ingress)(egress);
    end loop;

    return ret;
  end function;

  -- One-hot AND-OR mux of the ingress read data. An empty select
  -- yields a beat with valid low, which is what makes the beat path
  -- need no gating by the egress port state.
  function muxed_beat(select_one_hot: port_set_t;
                      frame: nsl_amba.axi4_stream.master_vector)
    return nsl_amba.axi4_stream.master_t
  is
    variable gate, acc: std_ulogic_vector(0 to mux_width_c-1);
  begin
    acc := (others => '0');

    for ingress in 0 to port_count_c-1
    loop
      gate := (others => select_one_hot(ingress));
      acc := acc or (gate and nsl_amba.axi4_stream.vector_pack(frame_config_c,
                                                               mux_elements_c,
                                                               frame(ingress)));
    end loop;

    return nsl_amba.axi4_stream.vector_unpack(frame_config_c, mux_elements_c, acc);
  end function;

  -- The copy is over once the last beat has been accepted by the
  -- register slice. What the slice does with it afterwards is of no
  -- concern to the ingress port, whose read side may be handed over to
  -- another egress port right away.
  function copy_done(beat: nsl_amba.axi4_stream.master_t;
                     ack: nsl_amba.axi4_stream.slave_t) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_valid(frame_config_c, beat)
      and nsl_amba.axi4_stream.is_last(frame_config_c, beat)
      and nsl_amba.axi4_stream.is_ready(out_config_c, ack);
  end function;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.want <= (others => (others => '0'));
      r.state <= (others => ST_RESET);
      r.scan_start <= (others => 0);
      r.candidate <= (others => 0);
      r.source <= (others => 0);
      r.locked <= (others => '0');
      r.reader <= (others => (others => '0'));
      r.taken <= (others => (others => '0'));
    end if;
  end process;

  transition: process(r, forward_i, read_beat_s, slice_ack_s) is
    variable want_v: port_set_vector(0 to port_count_c-1);
    variable candidate_v: index_vector(0 to port_count_c-1);
    variable granted_v, done_v: flag_vector(0 to port_count_c-1);
  begin
    for egress in 0 to port_count_c-1
    loop
      want_v(egress) := requesters(forward_i, egress);
      candidate_v(egress) := candidate_of(r.want(egress), r.locked, r.scan_start(egress));
      granted_v(egress) := claim_granted(r, egress);
      done_v(egress) := copy_done(read_beat_s(egress), slice_ack_s(egress));
    end loop;

    rin <= r;
    rin.want <= want_v;

    for egress in 0 to port_count_c-1
    loop
      case r.state(egress) is
        when ST_RESET =>
          rin.state(egress) <= ST_SCAN;

        when ST_SCAN =>
          if candidate_v(egress) >= 0 then
            rin.candidate(egress) <= candidate_v(egress);
            rin.state(egress) <= ST_CLAIM;
          end if;

        when ST_CLAIM =>
          if granted_v(egress) then
            rin.locked(r.candidate(egress)) <= '1';
            rin.source(egress) <= r.candidate(egress);
            rin.reader(r.candidate(egress))(egress) <= '1';
            rin.state(egress) <= ST_COPY;
          else
            rin.state(egress) <= ST_SCAN;
          end if;

        when ST_COPY =>
          if done_v(egress) then
            rin.reader(r.source(egress))(egress) <= '0';
            rin.taken(r.source(egress))(egress) <= '1';
            rin.state(egress) <= ST_ACK;
          end if;

        when ST_ACK =>
          rin.taken(r.source(egress))(egress) <= '0';
          rin.state(egress) <= ST_RELEASE;

        when ST_RELEASE =>
          rin.locked(r.source(egress)) <= '0';
          rin.scan_start(egress) <= wrap(r.source(egress) + 1);
          rin.state(egress) <= ST_SCAN;
      end case;
    end loop;
  end process;

  moore: process(r, slice_ack_s) is
    variable slice_ready_v: port_set_t;
  begin
    for egress in 0 to port_count_c-1
    loop
      if nsl_amba.axi4_stream.is_ready(out_config_c, slice_ack_s(egress)) then
        slice_ready_v(egress) := '1';
      else
        slice_ready_v(egress) := '0';
      end if;
    end loop;

    for ingress in 0 to port_count_c-1
    loop
      in_ack_s(ingress) <= nsl_amba.axi4_stream.accept(
        frame_config_c,
        any_set(r.reader(ingress) and slice_ready_v));
      forward_o(ingress).taken <= widen(r.taken(ingress));
    end loop;
  end process;

  ingress_slice: for ingress in 0 to port_count_c-1
  generate
    slice: nsl_amba.stream_fifo.axi4_stream_slice
      generic map(
        config_c => frame_config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => frame_i(ingress),
        in_o => frame_o(ingress),

        out_o => in_beat_s(ingress),
        out_i => in_ack_s(ingress)
        );
  end generate;

  egress_slice: for egress in 0 to port_count_c-1
  generate
    read_beat_s(egress) <= muxed_beat(read_by(r, egress), in_beat_s);
    slice_in_s(egress) <= nsl_amba.axi4_stream.transfer(out_config_c,
                                                       frame_config_c,
                                                       read_beat_s(egress));

    slice: nsl_amba.stream_fifo.axi4_stream_slice
      generic map(
        config_c => out_config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slice_in_s(egress),
        in_o => slice_ack_s(egress),

        out_o => out_o(egress),
        out_i => out_i(egress)
        );
  end generate;

end architecture;
