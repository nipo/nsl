library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.avalon_st.all;

-- Bridges between two Avalon-ST interfaces that differ only in
-- ready_latency (with ready_allowance = ready_latency on both sides).
--
-- When in/out ready latencies match, the adapter is a pure wire (any
-- has_ready combination is permitted). When they differ, both sides
-- must have has_ready = true and the bridge instantiates a small FSM:
--
--   in_i ─[ in.RL-deep ready-promise shift register ]─┐
--                                                     │
--                                                     ▼
--                                            ┌─ store_t FIFO ─┐
--                                            │  depth in.RL+1 │
--                                            └─────┬──────────┘
--                                                  │ pop when out_i.ready
--                                                  ▼
--                                  out.RL-deep beat delay pipeline ─→ out_o
--
-- Throughput is one beat per clock when downstream consumes at the
-- same rate.
entity avalon_st_ready_latency_adapter is
  generic(
    in_config_c  : config_t;
    out_config_c : config_t
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in  source_t;
    in_o : out sink_t;

    out_o : out source_t;
    out_i : in  sink_t
    );
end entity;

architecture beh of avalon_st_ready_latency_adapter is

  constant in_rl_c       : natural := in_config_c.ready_latency;
  constant out_rl_c      : natural := out_config_c.ready_latency;
  constant matched_c     : boolean := in_rl_c = out_rl_c;
  constant store_depth_c : positive := in_rl_c + 1;

begin

  -- Compile-time / elaboration checks. Concurrent asserts with
  -- constant conditions fire at elaboration.
  assert in_config_c.symbols_per_beat = out_config_c.symbols_per_beat
    report "symbols_per_beat must match between in and out"
    severity failure;
  assert in_config_c.data_bits_per_symbol = out_config_c.data_bits_per_symbol
    report "data_bits_per_symbol must match between in and out"
    severity failure;
  assert in_config_c.channel_width = out_config_c.channel_width
    report "channel_width must match between in and out"
    severity failure;
  assert in_config_c.error_width = out_config_c.error_width
    report "error_width must match between in and out"
    severity failure;
  assert in_config_c.packet_user_width = out_config_c.packet_user_width
    report "packet_user_width must match between in and out"
    severity failure;
  assert in_config_c.symbol_user_width = out_config_c.symbol_user_width
    report "symbol_user_width must match between in and out"
    severity failure;
  assert in_config_c.has_packet = out_config_c.has_packet
    report "has_packet must match between in and out"
    severity failure;
  assert in_config_c.has_empty = out_config_c.has_empty
    report "has_empty must match between in and out"
    severity failure;
  assert in_config_c.ready_allowance = in_config_c.ready_latency
    report "in_config.ready_allowance must equal in_config.ready_latency"
    severity failure;
  assert out_config_c.ready_allowance = out_config_c.ready_latency
    report "out_config.ready_allowance must equal out_config.ready_latency"
    severity failure;
  assert (not out_config_c.has_ready) or in_config_c.has_ready
    report "out has_ready requires in has_ready"
    severity failure;
  assert matched_c or (in_config_c.has_ready and out_config_c.has_ready)
    report "Non-matching ready_latency requires has_ready on both sides"
    severity failure;

  -- Pure-wire case: identical ready_latency. Any has_ready combination
  -- is allowed here; we re-derive in_o.ready instead of blindly passing
  -- out_i.ready, so that an undriven ready on a has_ready=false sink
  -- never propagates as a don't-care to a has_ready=true source.
  matched_gen: if matched_c generate
    out_o <= in_i;

    rd_both: if in_config_c.has_ready and out_config_c.has_ready generate
      in_o.ready <= out_i.ready;
    end generate;
    rd_in_only: if in_config_c.has_ready and not out_config_c.has_ready generate
      in_o.ready <= '1';
    end generate;
    rd_neither: if not in_config_c.has_ready generate
      in_o.ready <= '-';
    end generate;
  end generate;

  adapt_gen: if not matched_c generate

    type regs_t is record
      in_promise_sr  : std_ulogic_vector(in_rl_c-1 downto 0);
      store          : source_vector(0 to store_depth_c-1);
      store_count    : integer range 0 to store_depth_c;
      out_pipe_valid : std_ulogic_vector(out_rl_c-1 downto 0);
      out_pipe       : source_vector(0 to out_rl_c-1);
    end record;

    signal r, rin : regs_t;

  begin

    clock_proc: process(clock_i, reset_n_i) is
    begin
      if reset_n_i = '0' then
        r.store_count <= 0;
        if in_rl_c > 0 then
          r.in_promise_sr <= (others => '0');
        end if;
        if out_rl_c > 0 then
          r.out_pipe_valid <= (others => '0');
        end if;
      elsif rising_edge(clock_i) then
        r <= rin;
      end if;
    end process;

    comb_proc: process(r, in_i, out_i) is
      variable rv          : regs_t;
      variable in_ready_v  : std_ulogic;
      variable push_en     : boolean;
      variable pop_en      : boolean;
      variable pending     : natural;
      variable out_ready_v : boolean;
    begin
      rv := r;

      -- Count outstanding in-flight ready promises (beats committed
      -- to arrive but not yet received).
      pending := 0;
      for i in 0 to in_rl_c-1 loop
        if r.in_promise_sr(i) = '1' then
          pending := pending + 1;
        end if;
      end loop;

      -- We may issue ready when the store plus in-flight beats leaves
      -- at least one free slot. The invariant
      --   store_count + pending <= store_depth_c
      -- holds as long as we only assert in_ready_v when there's
      -- strict slack.
      if r.store_count + pending < store_depth_c then
        in_ready_v := '1';
      else
        in_ready_v := '0';
      end if;

      -- Whether a beat is being pushed this cycle. With in.RL = 0 the
      -- source presents valid same-cycle and we gate on our just-
      -- issued ready. With in.RL > 0 the source's valid_i is itself
      -- gated by ready we asserted in.RL cycles ago (sr tail).
      if in_rl_c = 0 then
        push_en := in_i.valid = '1' and in_ready_v = '1';
      else
        push_en := in_i.valid = '1' and r.in_promise_sr(in_rl_c-1) = '1';
      end if;

      -- Downstream effective ready.
      if out_config_c.has_ready then
        out_ready_v := out_i.ready = '1';
      else
        out_ready_v := true;
      end if;

      -- Commit a beat from store when the sink permits and we have
      -- something to deliver. With out.RL = 0 this becomes a true
      -- pop; with out.RL > 0 the beat lands in the delay pipeline.
      pop_en := out_ready_v and r.store_count > 0;

      -- Apply push/pop to store.
      if push_en and pop_en then
        for i in 0 to store_depth_c-2 loop
          rv.store(i) := r.store(i+1);
        end loop;
        if r.store_count >= 1 then
          rv.store(r.store_count-1) := in_i;
        end if;
      elsif push_en then
        rv.store(r.store_count) := in_i;
        rv.store_count := r.store_count + 1;
      elsif pop_en then
        for i in 0 to store_depth_c-2 loop
          rv.store(i) := r.store(i+1);
        end loop;
        rv.store_count := r.store_count - 1;
      end if;

      -- Shift the in-flight ready promise SR.
      if in_rl_c > 0 then
        rv.in_promise_sr := r.in_promise_sr(in_rl_c-2 downto 0) & in_ready_v;
      end if;

      -- Shift the output delay pipeline, then insert this cycle's
      -- commitment (or a valid='0' placeholder).
      if out_rl_c > 0 then
        for i in 1 to out_rl_c-1 loop
          rv.out_pipe(i) := r.out_pipe(i-1);
          rv.out_pipe_valid(i) := r.out_pipe_valid(i-1);
        end loop;
        if pop_en then
          rv.out_pipe(0) := r.store(0);
          rv.out_pipe_valid(0) := '1';
        else
          rv.out_pipe_valid(0) := '0';
        end if;
      end if;

      rin <= rv;

      -- Drive in_o.ready (or '-' if source can't be backpressured).
      if in_config_c.has_ready then
        in_o.ready <= in_ready_v;
      else
        in_o.ready <= '-';
      end if;

      -- Drive out_o.
      if out_rl_c > 0 then
        if r.out_pipe_valid(out_rl_c-1) = '1' then
          out_o <= r.out_pipe(out_rl_c-1);
        else
          out_o <= transfer_defaults(out_config_c);
        end if;
      else
        if r.store_count > 0 then
          out_o <= r.store(0);
        else
          out_o <= transfer_defaults(out_config_c);
        end if;
      end if;
    end process;

  end generate;

end architecture;
