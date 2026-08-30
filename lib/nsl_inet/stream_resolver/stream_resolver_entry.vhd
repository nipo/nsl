library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.stream.all;

-- Splices address resolution into an egress stream.
--
-- An input packet is [query block][remainder].  The query block is
-- held in registers and handed to the resolver as a standalone packet;
-- the remainder goes into the buffer fifo and the resolver's response
-- into the response fifo, both uncommitted.  Once the input packet is
-- in and the resolver has answered, either both fifos are committed
-- and the response blocks are emitted in front of the remainder, or
-- both are rolled back and nothing is emitted at all.
--
-- The whole remainder is buffered before anything is emitted: a
-- packet's fate has to be settled while it can still be taken back,
-- and a remainder that does not fit the buffer is a packet that cannot
-- be held.  Whether a packet fits therefore only depends on its size,
-- never on the resolution latency or on the output backpressure.
--
-- Packets dropped along the way -- a remainder overflowing the buffer,
-- a rejected response, an input packet ending inside its query block
-- -- leave no trace: the input is consumed to its last beat, the
-- response is consumed and discarded, and the next packet is processed
-- as usual.
entity stream_resolver_entry is
  generic(
    config_c : config_t;
    query_length_c : natural;
    buffer_depth_l2_c : natural := 11
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    query_o : out master_t;
    query_i : in slave_t;
    response_i : in master_t;
    response_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_resolver_entry is

  constant query_beats_c : natural
    := context_beat_count(config_c, (0 => query_length_c));
  constant buffer_depth_c : natural := 2 ** buffer_depth_l2_c;
  -- A response is the blocks of the layers below the resolver's
  -- sibling layer plus the echoed query block, a per-stack constant of
  -- a few beats.  A response that does not fit here is a configuration
  -- error, not a run-time condition.
  constant response_depth_l2_c : natural := 6;
  constant response_depth_c : natural := 2 ** response_depth_l2_c;

  type state_t is (
    -- Clearing the per-packet state
    ST_RESTART,
    -- Collecting the query block off the input
    ST_QUERY,
    -- Streaming the remainder into the buffer fifo
    ST_BODY,
    -- Consuming the rest of an input packet that will not be emitted
    ST_DRAIN,
    -- Input packet is in, waiting for the resolver verdict
    ST_WAIT,
    -- Handing both fifos over to their reader side
    ST_COMMIT,
    -- Taking both fifos back
    ST_CANCEL,
    -- Emitting the response blocks
    ST_RESPONSE,
    -- Emitting the buffered remainder
    ST_REMAINDER
    );

  type verdict_t is (
    VERDICT_PENDING,
    VERDICT_RESOLVED,
    VERDICT_FAILED
    );

  type regs_t is
  record
    state: state_t;
    -- Query block beats, as received
    query: master_vector(0 to query_beats_c-1);
    query_fillness: natural range 0 to query_beats_c;
    query_to_go: natural range 0 to query_beats_c;
    verdict: verdict_t;
    response_count: natural range 0 to response_depth_c;
    body_count: natural range 0 to buffer_depth_c;
    -- Input packet had no beat past its query block
    body_empty: boolean;
    -- Packet will not be emitted whatever the verdict
    dropped: boolean;
    -- Reject flag carried by the input packet's last beat
    in_rejected: boolean;
  end record;

  signal r, rin: regs_t;

  signal buffer_in_s, buffer_out_s : bus_t;
  signal buffer_commit_s, buffer_rollback_s : std_ulogic;
  signal response_in_s, response_out_s : bus_t;
  signal response_commit_s, response_rollback_s : std_ulogic;

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

      assert not (is_valid(config_c, response_i)
                  and r.verdict = VERDICT_PENDING
                  and r.response_count = response_depth_c)
        report "Resolver response is larger than the response buffer"
        severity failure;
    end if;
  end process;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESTART;
      r.query_to_go <= 0;
      r.verdict <= VERDICT_PENDING;
      r.response_count <= 0;
    end if;
  end process;

  -- The only fifo signals the transition depends upon are the fifo
  -- outputs, registered inside the fifos; the master sides of the
  -- fifo pairs are combinational and never read here.
  transition: process(r, in_i, query_i, response_i, out_i,
                      buffer_in_s.s, buffer_out_s.m,
                      response_in_s.s, response_out_s.m) is
  begin
    rin <= r;

    -- The query block is handed to the resolver while the remainder
    -- keeps streaming in.
    if r.query_to_go /= 0 and is_ready(config_c, query_i) then
      rin.query_to_go <= r.query_to_go - 1;
    end if;

    -- The response is collected in the background; its verdict may
    -- come before or after the end of the input packet.
    if r.verdict = VERDICT_PENDING
      and is_valid(config_c, response_i)
      and is_ready(config_c, response_in_s.s) then
      rin.response_count <= r.response_count + 1;
      if is_last(config_c, response_i) then
        if is_rejected(config_c, response_i) then
          rin.verdict <= VERDICT_FAILED;
        else
          rin.verdict <= VERDICT_RESOLVED;
        end if;
      end if;
    end if;

    case r.state is
      when ST_RESTART =>
        rin.state <= ST_QUERY;
        rin.query_fillness <= 0;
        rin.verdict <= VERDICT_PENDING;
        rin.response_count <= 0;
        rin.body_count <= 0;
        rin.body_empty <= true;
        rin.dropped <= false;
        rin.in_rejected <= false;

      when ST_QUERY =>
        if is_valid(config_c, in_i) then
          rin.query(r.query_fillness) <= in_i;

          if r.query_fillness = query_beats_c - 1 then
            rin.query_fillness <= 0;
            rin.query_to_go <= query_beats_c;
            rin.in_rejected <= is_rejected(config_c, in_i);
            if is_last(config_c, in_i) then
              rin.body_empty <= true;
              rin.state <= ST_WAIT;
            else
              rin.body_empty <= false;
              rin.state <= ST_BODY;
            end if;
          elsif is_last(config_c, in_i) then
            -- Packet ends inside its query block, there is nothing to
            -- resolve and nothing to emit.
            rin.query_fillness <= 0;
          else
            rin.query_fillness <= r.query_fillness + 1;
          end if;
        end if;

      when ST_BODY =>
        if is_valid(config_c, in_i) then
          if r.body_count = buffer_depth_c then
            -- One beat more than the buffer holds: the packet cannot
            -- be kept until the verdict is known.
            rin.dropped <= true;
            rin.state <= ST_DRAIN;
          elsif is_ready(config_c, buffer_in_s.s) then
            rin.body_count <= r.body_count + 1;
            if is_last(config_c, in_i) then
              rin.in_rejected <= is_rejected(config_c, in_i);
              rin.state <= ST_WAIT;
            end if;
          end if;
        end if;

      when ST_DRAIN =>
        if is_valid(config_c, in_i) and is_last(config_c, in_i) then
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        -- The resolver answers every query, so a dropped packet still
        -- has a response to consume before the next packet may go.
        case r.verdict is
          when VERDICT_PENDING =>
            null;

          when VERDICT_RESOLVED =>
            if r.dropped then
              rin.state <= ST_CANCEL;
            else
              rin.state <= ST_COMMIT;
            end if;

          when VERDICT_FAILED =>
            rin.state <= ST_CANCEL;
        end case;

      when ST_COMMIT =>
        rin.state <= ST_RESPONSE;

      when ST_CANCEL =>
        rin.state <= ST_RESTART;

      when ST_RESPONSE =>
        if is_valid(config_c, response_out_s.m)
          and is_ready(config_c, out_i)
          and is_last(config_c, response_out_s.m) then
          if r.body_empty then
            rin.state <= ST_RESTART;
          else
            rin.state <= ST_REMAINDER;
          end if;
        end if;

      when ST_REMAINDER =>
        if is_valid(config_c, buffer_out_s.m)
          and is_ready(config_c, out_i)
          and is_last(config_c, buffer_out_s.m) then
          rin.state <= ST_RESTART;
        end if;
    end case;
  end process;

  -- Outputs only depend on the state registers and on the fifo status
  -- signals, which are registered inside the fifos.
  moore: process(r, buffer_in_s.s, buffer_out_s.m,
                 response_in_s.s, response_out_s.m) is
    variable beat_v: master_t;
    variable last_v: boolean;
  begin
    case r.state is
      when ST_QUERY | ST_DRAIN =>
        in_o <= accept(config_c, true);

      when ST_BODY =>
        in_o <= accept(config_c, is_ready(config_c, buffer_in_s.s));

      when others =>
        in_o <= accept(config_c, false);
    end case;

    if r.query_to_go /= 0 then
      query_o <= reject_set(config_c,
                            transfer(config_c,
                                     r.query(query_beats_c - r.query_to_go),
                                     force_valid => true,
                                     valid => true,
                                     force_last => true,
                                     last => r.query_to_go = 1),
                            false);
    else
      query_o <= transfer_defaults(config_c);
    end if;

    response_o <= accept(config_c,
                         r.verdict = VERDICT_PENDING
                         and is_ready(config_c, response_in_s.s));

    buffer_commit_s <= to_logic(r.state = ST_COMMIT);
    buffer_rollback_s <= to_logic(r.state = ST_CANCEL);
    response_commit_s <= to_logic(r.state = ST_COMMIT);
    response_rollback_s <= to_logic(r.state = ST_CANCEL);

    case r.state is
      when ST_RESPONSE =>
        -- Response blocks are the head of the emitted packet: their
        -- last beat only ends the packet when there is no remainder,
        -- and then it carries the reject flag of the input packet.
        beat_v := response_out_s.m;
        last_v := r.body_empty and is_last(config_c, beat_v);
        out_o <= reject_set(config_c,
                            transfer(config_c, beat_v,
                                     force_last => true,
                                     last => last_v),
                            last_v and r.in_rejected);

      when ST_REMAINDER =>
        out_o <= buffer_out_s.m;

      when others =>
        out_o <= transfer_defaults(config_c);
    end case;
  end process;

  buffer_in_s.m <= transfer(config_c, in_i,
                            force_valid => true,
                            valid => r.state = ST_BODY
                                     and is_valid(config_c, in_i)
                                     and r.body_count < buffer_depth_c);
  buffer_out_s.s <= accept(config_c,
                           r.state = ST_REMAINDER and is_ready(config_c, out_i));

  response_in_s.m <= transfer(config_c, response_i,
                              force_valid => true,
                              valid => r.verdict = VERDICT_PENDING
                                       and is_valid(config_c, response_i));
  response_out_s.s <= accept(config_c,
                             r.state = ST_RESPONSE and is_ready(config_c, out_i));

  packet_buffer: nsl_amba.stream_fifo.axi4_stream_fifo_cancellable
    generic map(
      config_c => config_c,
      word_count_l2_c => buffer_depth_l2_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i => buffer_in_s.m,
      in_o => buffer_in_s.s,
      in_commit_i => buffer_commit_s,
      in_rollback_i => buffer_rollback_s,
      in_free_o => open,

      out_o => buffer_out_s.m,
      out_i => buffer_out_s.s,
      out_available_o => open
      );

  response_buffer: nsl_amba.stream_fifo.axi4_stream_fifo_cancellable
    generic map(
      config_c => config_c,
      word_count_l2_c => response_depth_l2_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i => response_in_s.m,
      in_o => response_in_s.s,
      in_commit_i => response_commit_s,
      in_rollback_i => response_rollback_s,
      in_free_o => open,

      out_o => response_out_s.m,
      out_i => response_out_s.s,
      out_available_o => open
      );

end architecture;
