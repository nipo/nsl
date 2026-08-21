library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, nsl_memory, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_math.fixed.all;
use nsl_simulation.logging.all;

-- One fifo under paced traffic, with a scoreboard on the payload and a
-- reference model of the fill level built from the handshakes seen at
-- the fifo ports.
entity fifo_paced_case is
  generic(
    name_c: string;
    depth_c: positive;
    clock_count_c: integer range 1 to 2;
    -- Instantiate fifo_homogeneous by hand instead of going through
    -- the axi4-stream wrapper. Gives access to out_available_min_o and
    -- to register_counters_c.
    direct_c: boolean := false;
    register_counters_c: boolean := false
    );
  port(
    clock_i: in std_ulogic_vector(0 to clock_count_c-1);
    reset_n_i: in std_ulogic;

    in_rate_i: in ufixed(-1 downto -8);
    out_rate_i: in ufixed(-1 downto -8);
    in_enable_i: in std_ulogic;
    out_enable_i: in std_ulogic;

    check_enable_i: in std_ulogic;
    -- Asserted after both sides stayed idle long enough for every
    -- count to have converged.
    settled_i: in std_ulogic;

    written_o: out natural;
    transferred_o: out natural;
    max_used_o: out natural
    );
end entity;

architecture beh of fifo_paced_case is

  constant config_c: config_t := config(1);
  constant prbs_init_c: prbs_state(30 downto 0) := x"deadbee"&"111";
  -- Counters exported by the fifo are one cycle late when registered.
  constant count_delay_c: natural := if_else(register_counters_c, 1, 0);

  alias in_clock_s: std_ulogic is clock_i(0);
  alias out_clock_s: std_ulogic is clock_i(clock_count_c-1);

  signal source_s, fifo_in_s, fifo_out_s, sink_s: bus_t;

  signal available_s: integer range 0 to depth_c+1;
  signal available_min_s, free_s: integer range 0 to depth_c;

  signal source_state_s, sink_state_s: prbs_state(30 downto 0);
  signal write_count_s, read_count_s, max_used_s: natural;
  -- Handshakes seen on the far side of the pacers, to tell a fifo
  -- fault from a testbench one.
  signal source_count_s, sink_count_s: natural;
  -- Fill level as the fifo ports saw it one clock ago, per side.
  signal in_used_prev_s, out_used_prev_s: natural;

begin

  source_s.m <= transfer(config_c,
                         bytes => prbs_byte_string(source_state_s, prbs31, 1),
                         valid => in_enable_i = '1');

  source: process(in_clock_s, reset_n_i) is
  begin
    if rising_edge(in_clock_s) then
      if is_valid(config_c, source_s.m) and is_ready(config_c, source_s.s) then
        source_state_s <= prbs_forward(source_state_s, prbs31, 8);
        source_count_s <= source_count_s + 1;
      end if;
    end if;

    if reset_n_i = '0' then
      source_state_s <= prbs_init_c;
      source_count_s <= 0;
    end if;
  end process;

  in_pacer: nsl_amba.stream_traffic.axi4_stream_pacer_dynamic
    generic map(
      config_c => config_c,
      probability_denom_l2_c => 8
      )
    port map(
      clock_i => in_clock_s,
      reset_n_i => reset_n_i,

      probability_i => in_rate_i,

      in_i => source_s.m,
      in_o => source_s.s,

      out_o => fifo_in_s.m,
      out_i => fifo_in_s.s
      );

  wrapped: if not direct_c
  generate
    dut: nsl_amba.stream_fifo.axi4_stream_fifo
      generic map(
        config_c => config_c,
        depth_c => depth_c,
        clock_count_c => clock_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => fifo_in_s.m,
        in_o => fifo_in_s.s,
        in_free_o => free_s,

        out_o => fifo_out_s.m,
        out_i => fifo_out_s.s,
        out_available_o => available_s
        );

    available_min_s <= 0;
  end generate;

  direct: if direct_c
  generate
    signal in_data_s, out_data_s: std_ulogic_vector(7 downto 0);
    signal in_valid_s, in_ready_s, out_valid_s, out_ready_s: std_ulogic;
  begin
    dut: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => 8,
        word_count_c => depth_c,
        clock_count_c => clock_count_c,
        register_counters_c => register_counters_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        in_data_i => in_data_s,
        in_valid_i => in_valid_s,
        in_ready_o => in_ready_s,
        in_free_o => free_s,

        out_data_o => out_data_s,
        out_valid_o => out_valid_s,
        out_ready_i => out_ready_s,
        out_available_min_o => available_min_s,
        out_available_o => available_s
        );

    in_data_s <= std_ulogic_vector(value(config_c, fifo_in_s.m));
    in_valid_s <= to_logic(is_valid(config_c, fifo_in_s.m));
    fifo_in_s.s <= accept(config_c, in_ready_s = '1');

    fifo_out_s.m <= transfer(config_c,
                             value => unsigned(out_data_s),
                             valid => out_valid_s = '1');
    out_ready_s <= to_logic(is_ready(config_c, fifo_out_s.s));
  end generate;

  out_pacer: nsl_amba.stream_traffic.axi4_stream_pacer_dynamic
    generic map(
      config_c => config_c,
      probability_denom_l2_c => 8
      )
    port map(
      clock_i => out_clock_s,
      reset_n_i => reset_n_i,

      probability_i => out_rate_i,

      in_i => fifo_out_s.m,
      in_o => fifo_out_s.s,

      out_o => sink_s.m,
      out_i => sink_s.s
      );

  sink_s.s <= accept(config_c, out_enable_i = '1');

  sink: process(out_clock_s, reset_n_i) is
  begin
    if rising_edge(out_clock_s) then
      if is_valid(config_c, sink_s.m) and is_ready(config_c, sink_s.s) then
        assert bytes(config_c, sink_s.m) = prbs_byte_string(sink_state_s, prbs31, 1)
          report name_c & ": payload mismatch, got "
          & to_string(bytes(config_c, sink_s.m))
          & ", expected " & to_string(prbs_byte_string(sink_state_s, prbs31, 1))
          & " at word " & to_string(read_count_s)
          severity failure;

        sink_state_s <= prbs_forward(sink_state_s, prbs31, 8);
        sink_count_s <= sink_count_s + 1;
      end if;
    end if;

    if reset_n_i = '0' then
      sink_state_s <= prbs_init_c;
      sink_count_s <= 0;
    end if;
  end process;

  -- Reference model: what actually crossed the fifo ports.
  write_counter: process(in_clock_s, reset_n_i) is
  begin
    if rising_edge(in_clock_s) then
      if is_valid(config_c, fifo_in_s.m) and is_ready(config_c, fifo_in_s.s) then
        write_count_s <= write_count_s + 1;
      end if;
    end if;

    if reset_n_i = '0' then
      write_count_s <= 0;
    end if;
  end process;

  read_counter: process(out_clock_s, reset_n_i) is
  begin
    if rising_edge(out_clock_s) then
      if is_valid(config_c, fifo_out_s.m) and is_ready(config_c, fifo_out_s.s) then
        read_count_s <= read_count_s + 1;
      end if;
    end if;

    if reset_n_i = '0' then
      read_count_s <= 0;
    end if;
  end process;

  written_o <= write_count_s;
  transferred_o <= read_count_s;
  max_used_o <= max_used_s;

  -- Input side counter never announces more room than there is, and
  -- announces none exactly when the fifo refuses words.
  in_monitor: process(in_clock_s, reset_n_i) is
    variable used, reference: natural;
  begin
    if rising_edge(in_clock_s) then
      used := write_count_s - read_count_s;
      -- A registered count tells about the fill level of one cycle ago.
      reference := if_else(count_delay_c = 0, used, in_used_prev_s);

      assert used <= depth_c
        report name_c & ": fifo holds " & to_string(used)
        & " words for a depth of " & to_string(depth_c)
        severity failure;

      if check_enable_i = '1' then
        assert free_s + reference <= depth_c
          report name_c & ": in_free_o " & to_string(free_s)
          & " announces more room than the " & to_string(depth_c - reference)
          & " there is" severity failure;

        if count_delay_c = 0 then
          assert (free_s /= 0) = is_ready(config_c, fifo_in_s.s)
            report name_c & ": in_free_o " & to_string(free_s)
            & " disagrees with in_ready_o" severity failure;
        end if;
      end if;

      in_used_prev_s <= used;
      if used > max_used_s then
        max_used_s <= used;
      end if;
    end if;

    if reset_n_i = '0' then
      in_used_prev_s <= 0;
      max_used_s <= 0;
    end if;
  end process;

  -- Output side counters never announce more words than there are, and
  -- a word at the output port is one of them.
  out_monitor: process(out_clock_s, reset_n_i) is
    variable used, reference: natural;
  begin
    if rising_edge(out_clock_s) then
      used := write_count_s - read_count_s;
      reference := if_else(count_delay_c = 0, used, out_used_prev_s);

      if check_enable_i = '1' then
        assert available_s <= reference
          report name_c & ": out_available_o " & to_string(available_s)
          & " announces more than the " & to_string(reference)
          & " words there is" severity failure;

        assert available_min_s <= available_s
          report name_c & ": out_available_min_o " & to_string(available_min_s)
          & " above out_available_o " & to_string(available_s)
          severity failure;

        if count_delay_c = 0 and is_valid(config_c, fifo_out_s.m) then
          assert available_s >= 1
            report name_c & ": out_available_o is zero while a word is presented"
            severity failure;

          if direct_c then
            assert available_min_s = available_s - 1
              report name_c & ": out_available_min_o " & to_string(available_min_s)
              & " does not exclude the presented word from out_available_o "
              & to_string(available_s) severity failure;
          end if;
        end if;
      end if;

      out_used_prev_s <= used;
    end if;

    if reset_n_i = '0' then
      out_used_prev_s <= 0;
    end if;
  end process;

  -- Once both sides stopped, no position is stale anymore and every
  -- count must be the exact fill level, wherever words sit inside.
  settle_check: process is
    variable used: natural;
  begin
    wait until settled_i = '1';

    used := write_count_s - read_count_s;

    assert source_count_s = write_count_s
      report name_c & ": source handed over " & to_string(source_count_s)
      & " words, fifo took " & to_string(write_count_s)
      severity failure;

    assert sink_count_s = read_count_s
      report name_c & ": fifo gave " & to_string(read_count_s)
      & " words, sink took " & to_string(sink_count_s)
      severity failure;

    assert available_s = used
      report name_c & ": settled out_available_o is " & to_string(available_s)
      & " for " & to_string(used) & " words held"
      severity failure;

    assert free_s = depth_c - used
      report name_c & ": settled in_free_o is " & to_string(free_s)
      & " for " & to_string(depth_c - used) & " words of room"
      severity failure;

    if direct_c then
      assert available_min_s = used - if_else(is_valid(config_c, fifo_out_s.m), 1, 0)
        report name_c & ": settled out_available_min_o is "
        & to_string(available_min_s) & " for " & to_string(used) & " words held"
        severity failure;
    end if;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_simulation;
use nsl_data.text.all;
use nsl_math.fixed.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  constant case_count_c: integer := 4;

  type natural_vector is array(integer range <>) of natural;

  -- Probability of the pacers letting a beat through. The comparison
  -- inside the pacer is an inclusive one, so the top code point always
  -- passes and the bottom one only passes one time in 256.
  subtype rate_t is ufixed(-1 downto -8);
  constant rate_max_c: rate_t := to_ufixed(255.0/256.0, -1, -8);
  constant rate_high_c: rate_t := to_ufixed(0.75, -1, -8);
  constant rate_half_c: rate_t := to_ufixed(0.5, -1, -8);
  constant rate_low_c: rate_t := to_ufixed(0.25, -1, -8);
  constant rate_min_c: rate_t := to_ufixed(0.0, -1, -8);

  signal clock_s: std_ulogic_vector(0 to 2);
  signal reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal in_rate_s, out_rate_s: rate_t;
  signal in_enable_s, out_enable_s: std_ulogic;
  signal check_enable_s, settled_s: std_ulogic;

  signal written_s, transferred_s, max_used_s: natural_vector(0 to case_count_c-1);

  procedure quiesce(signal in_enable, out_enable, settled: out std_ulogic) is
  begin
    in_enable <= '0';
    out_enable <= '0';
    wait for 2 us;
    settled <= '1';
    wait for 100 ns;
    settled <= '0';
    wait for 100 ns;
  end procedure;

begin

  stim: process is
    variable mark: natural_vector(0 to case_count_c-1);
  begin
    done_s(0) <= '0';
    in_enable_s <= '0';
    out_enable_s <= '0';
    check_enable_s <= '0';
    settled_s <= '0';
    in_rate_s <= rate_max_c;
    out_rate_s <= rate_max_c;

    -- Keep every stimulus change off the clock grid. A change landing
    -- on an edge reaches the fifo ports and the checkers through
    -- different numbers of delta cycles, and they would then disagree
    -- on what happened during that very cycle.
    wait for 500 ns + 100 ps;
    check_enable_s <= '1';

    -- Fill to the brim and stay there.
    log_info("Fast in, slow out");
    in_rate_s <= rate_max_c;
    out_rate_s <= rate_min_c;
    in_enable_s <= '1';
    out_enable_s <= '1';
    wait for 8 us;
    quiesce(in_enable_s, out_enable_s, settled_s);

    -- Drain and stay empty.
    log_info("Slow in, fast out");
    in_rate_s <= rate_min_c;
    out_rate_s <= rate_max_c;
    in_enable_s <= '1';
    out_enable_s <= '1';
    wait for 8 us;
    quiesce(in_enable_s, out_enable_s, settled_s);

    -- Both sides wide open, measure what goes through.
    log_info("Matched rates, wide open");
    in_rate_s <= rate_max_c;
    out_rate_s <= rate_max_c;
    in_enable_s <= '1';
    out_enable_s <= '1';
    for i in mark'range
    loop
      mark(i) := transferred_s(i);
    end loop;
    wait for 10 us;
    for i in mark'range
    loop
      log_info("Case " & to_string(i) & ": " & to_string(transferred_s(i) - mark(i))
               & " words in 10 us");
    end loop;
    quiesce(in_enable_s, out_enable_s, settled_s);

    log_info("Matched rates, half duty");
    in_rate_s <= rate_half_c;
    out_rate_s <= rate_half_c;
    in_enable_s <= '1';
    out_enable_s <= '1';
    wait for 6 us;
    quiesce(in_enable_s, out_enable_s, settled_s);

    log_info("Producer slower than consumer");
    in_rate_s <= rate_low_c;
    out_rate_s <= rate_high_c;
    in_enable_s <= '1';
    out_enable_s <= '1';
    wait for 6 us;
    quiesce(in_enable_s, out_enable_s, settled_s);

    log_info("Consumer slower than producer");
    in_rate_s <= rate_high_c;
    out_rate_s <= rate_low_c;
    in_enable_s <= '1';
    out_enable_s <= '1';
    wait for 6 us;
    quiesce(in_enable_s, out_enable_s, settled_s);

    -- Flip between the two extremes without letting anything settle.
    log_info("Abrupt rate flips");
    in_enable_s <= '1';
    out_enable_s <= '1';
    for i in 0 to 9
    loop
      in_rate_s <= rate_max_c;
      out_rate_s <= rate_min_c;
      wait for 700 ns;
      in_rate_s <= rate_min_c;
      out_rate_s <= rate_max_c;
      wait for 700 ns;
    end loop;
    quiesce(in_enable_s, out_enable_s, settled_s);

    -- Final drain, everything that got in must have got out.
    log_info("Drain");
    in_rate_s <= rate_min_c;
    out_rate_s <= rate_max_c;
    in_enable_s <= '0';
    out_enable_s <= '1';
    wait for 4 us;
    quiesce(in_enable_s, out_enable_s, settled_s);

    for i in 0 to case_count_c-1
    loop
      log_info("Case " & to_string(i) & ": " & to_string(transferred_s(i))
               & " words through, peak fill " & to_string(max_used_s(i)));

      assert transferred_s(i) = written_s(i)
        report "Case " & to_string(i) & ": " & to_string(written_s(i))
        & " words in, " & to_string(transferred_s(i)) & " words out"
        severity failure;

      assert transferred_s(i) > 1000
        report "Case " & to_string(i) & ": only " & to_string(transferred_s(i))
        & " words went through" severity failure;
    end loop;

    -- Depth is what the fifo holds, no more, no less.
    assert max_used_s(0) = 16 and max_used_s(1) = 5
      and max_used_s(2) = 16 and max_used_s(3) = 8
      report "Peak fill levels did not reach the announced depths"
      severity failure;

    done_s(0) <= '1';
    wait;
  end process;

  -- Power of two depth, single clock.
  case0: entity work.fifo_paced_case
    generic map(
      name_c => "sync16",
      depth_c => 16,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_s(0),
      reset_n_i => reset_n_s,
      in_rate_i => in_rate_s,
      out_rate_i => out_rate_s,
      in_enable_i => in_enable_s,
      out_enable_i => out_enable_s,
      check_enable_i => check_enable_s,
      settled_i => settled_s,
      written_o => written_s(0),
      transferred_o => transferred_s(0),
      max_used_o => max_used_s(0)
      );

  -- Depth one above a power of two, single clock: positions wrap at
  -- five, both the address and the count arithmetic must follow.
  case1: entity work.fifo_paced_case
    generic map(
      name_c => "sync5",
      depth_c => 5,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_s(0),
      reset_n_i => reset_n_s,
      in_rate_i => in_rate_s,
      out_rate_i => out_rate_s,
      in_enable_i => in_enable_s,
      out_enable_i => out_enable_s,
      check_enable_i => check_enable_s,
      settled_i => settled_s,
      written_o => written_s(1),
      transferred_o => transferred_s(1),
      max_used_o => max_used_s(1)
      );

  -- Unrelated clocks, positions cross as gray code.
  case2: entity work.fifo_paced_case
    generic map(
      name_c => "async16",
      depth_c => 16,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => clock_s(1),
      clock_i(1) => clock_s(2),
      reset_n_i => reset_n_s,
      in_rate_i => in_rate_s,
      out_rate_i => out_rate_s,
      in_enable_i => in_enable_s,
      out_enable_i => out_enable_s,
      check_enable_i => check_enable_s,
      settled_i => settled_s,
      written_o => written_s(2),
      transferred_o => transferred_s(2),
      max_used_o => max_used_s(2)
      );

  -- Straight to the fifo, with registered counters.
  case3: entity work.fifo_paced_case
    generic map(
      name_c => "direct8",
      depth_c => 8,
      clock_count_c => 1,
      direct_c => true,
      register_counters_c => true
      )
    port map(
      clock_i(0) => clock_s(0),
      reset_n_i => reset_n_s,
      in_rate_i => in_rate_s,
      out_rate_i => out_rate_s,
      in_enable_i => in_enable_s,
      out_enable_i => out_enable_s,
      check_enable_i => check_enable_s,
      settled_i => settled_s,
      written_o => written_s(3),
      transferred_o => transferred_s(3),
      max_used_o => max_used_s(3)
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => clock_s'length,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 7 ns,
      clock_period(2) => 11 ns,
      reset_duration => (others => 32 ns),
      clock_o => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
