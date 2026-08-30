library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.axi4_stream.all;

-- Shares one resolver between several query sources.
--
-- Queries are funneled to the resolver one packet at a time, sources
-- taken in round-robin order, and the source of every granted query is
-- pushed into an index fifo.  Responses come back in query order, so
-- dispatching a response is a matter of reading the fifo head and
-- popping it on the response's last beat.
--
-- The index fifo bounds the count of queries that may be outstanding:
-- while it is full no query is granted, which backpressures the
-- sources.  Packets are forwarded beat for beat, so the reject flag
-- and the keep pattern of both directions reach their peer untouched.
entity stream_resolver_arbiter is
  generic(
    config_c : config_t;
    source_count_c : positive;
    pending_count_l2_c : natural := 2
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    query_i : in master_vector(0 to source_count_c-1);
    query_o : out slave_vector(0 to source_count_c-1);
    response_o : out master_vector(0 to source_count_c-1);
    response_i : in slave_vector(0 to source_count_c-1);

    resolver_query_o : out master_t;
    resolver_query_i : in slave_t;
    resolver_response_i : in master_t;
    resolver_response_o : out slave_t
    );
end entity;

architecture beh of stream_resolver_arbiter is

  constant pending_count_c : natural := 2 ** pending_count_l2_c;

  subtype source_index_t is natural range 0 to source_count_c-1;
  type source_index_vector is array(natural range <>) of source_index_t;

  -- Outcome of the round-robin scan of the query ports.
  type selection_t is
  record
    valid: boolean;
    index: source_index_t;
  end record;

  -- Round-robin scan, resuming after the source served last.  Going
  -- through the candidates backwards leaves the nearest one selected.
  -- The whole priority cone lands in one register, it never reaches a
  -- decision on its own.
  function scan(query: master_vector;
                served: source_index_t) return selection_t
  is
    variable ret: selection_t := (valid => false, index => 0);
  begin
    for k in source_count_c-1 downto 0
    loop
      if is_valid(config_c, query((served + 1 + k) mod source_count_c)) then
        ret := (valid => true,
                index => (served + 1 + k) mod source_count_c);
      end if;
    end loop;
    return ret;
  end function;

  type funnel_state_t is (
    -- Picking the next source to serve
    FUNNEL_IDLE,
    -- Forwarding one query packet
    FUNNEL_BUSY
    );

  type regs_t is
  record
    funnel: funnel_state_t;
    source: source_index_t;
    -- Scan of the query ports, one cycle behind them
    selection: selection_t;
    fifo: source_index_vector(0 to pending_count_c-1);
    fillness: natural range 0 to pending_count_c;
  end record;

  signal r, rin: regs_t;

begin

  assert config_c.has_last
    report "Configuration must have last signal"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.funnel <= FUNNEL_IDLE;
      r.source <= 0;
      r.selection.valid <= false;
      r.fillness <= 0;
    end if;
  end process;

  transition: process(r, query_i, resolver_query_i,
                      resolver_response_i, response_i) is
    variable push_v, pop_v: boolean;
  begin
    rin <= r;

    rin.selection <= scan(query_i, r.source);

    -- A grant uses the scan of the previous cycle, confirmed by the
    -- valid of the selected source: the registered selection may lag
    -- a query appearing, it may never invent one, as a valid beat
    -- stays valid until it is accepted.
    push_v := r.funnel = FUNNEL_IDLE
              and r.selection.valid
              and is_valid(config_c, query_i(r.selection.index))
              and r.fillness < pending_count_c;

    pop_v := r.fillness > 0
             and is_valid(config_c, resolver_response_i)
             and is_ready(config_c, response_i(r.fifo(0)))
             and is_last(config_c, resolver_response_i);

    case r.funnel is
      when FUNNEL_IDLE =>
        if push_v then
          rin.source <= r.selection.index;
          rin.funnel <= FUNNEL_BUSY;
        end if;

      when FUNNEL_BUSY =>
        if is_valid(config_c, query_i(r.source))
          and is_ready(config_c, resolver_query_i)
          and is_last(config_c, query_i(r.source)) then
          rin.funnel <= FUNNEL_IDLE;
        end if;
    end case;

    if pop_v then
      for i in 0 to pending_count_c-2
      loop
        rin.fifo(i) <= r.fifo(i+1);
      end loop;
    end if;

    if push_v then
      if pop_v then
        rin.fifo(r.fillness-1) <= r.selection.index;
      else
        rin.fifo(r.fillness) <= r.selection.index;
      end if;
    end if;

    if push_v and not pop_v then
      rin.fillness <= r.fillness + 1;
    elsif pop_v and not push_v then
      rin.fillness <= r.fillness - 1;
    end if;
  end process;

  mealy: process(r, query_i, resolver_query_i,
                 resolver_response_i, response_i) is
    variable destination_v: source_index_t;
  begin
    destination_v := r.fifo(0);

    resolver_query_o <= transfer(config_c, query_i(r.source),
                                 force_valid => true,
                                 valid => r.funnel = FUNNEL_BUSY
                                          and is_valid(config_c,
                                                       query_i(r.source)));

    for i in query_o'range
    loop
      query_o(i) <= accept(config_c,
                           r.funnel = FUNNEL_BUSY
                           and i = r.source
                           and is_ready(config_c, resolver_query_i));
    end loop;

    resolver_response_o <= accept(config_c,
                                  r.fillness > 0
                                  and is_ready(config_c,
                                               response_i(destination_v)));

    for i in response_o'range
    loop
      response_o(i) <= transfer(config_c, resolver_response_i,
                                force_valid => true,
                                valid => r.fillness > 0
                                         and i = destination_v
                                         and is_valid(config_c,
                                                      resolver_response_i));
    end loop;
  end process;

end architecture;
