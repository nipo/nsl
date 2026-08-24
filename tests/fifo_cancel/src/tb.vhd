library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_simulation, nsl_logic;
use nsl_logic.bool.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  constant data_width_c: integer := 8;
  constant word_count_c: integer := 16;
  -- Cycles a handshake may be waited for before the testbench gives up.
  constant timeout_c: integer := 1000;
  -- Cycles left for the position crossings to settle before a counter
  -- is looked at.
  constant settle_cycle_count_c: integer := 8;

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector is array(natural range <>) of word_t;

  subtype free_t is integer range 0 to word_count_c;
  type free_vector is array(natural range <>) of free_t;
  subtype available_t is integer range 0 to word_count_c+1;
  type available_vector is array(natural range <>) of available_t;

  type boolean_vector is array(natural range <>) of boolean;

  -- Cancellable fifos under test, one per side combination.
  constant both_c: natural := 0;
  constant in_side_c: natural := 1;
  constant out_side_c: natural := 2;
  constant dut_count_c: natural := 3;

  constant in_cancel_cfg_c: boolean_vector(0 to dut_count_c-1)
    := (both_c => true, in_side_c => true, out_side_c => false);
  constant out_cancel_cfg_c: boolean_vector(0 to dut_count_c-1)
    := (both_c => true, in_side_c => false, out_side_c => true);

  signal clock_s: std_ulogic_vector(0 to 0);
  signal reset_n_s: std_ulogic_vector(0 to 0);
  signal done_s: std_ulogic_vector(0 to 0);

  signal in_data_s, out_data_s: word_vector(0 to dut_count_c-1);
  signal in_valid_s, in_ready_s: std_ulogic_vector(0 to dut_count_c-1);
  signal in_commit_s, in_rollback_s: std_ulogic_vector(0 to dut_count_c-1);
  signal out_valid_s, out_ready_s: std_ulogic_vector(0 to dut_count_c-1);
  signal out_commit_s, out_rollback_s: std_ulogic_vector(0 to dut_count_c-1);
  signal in_free_s: free_vector(0 to dut_count_c-1);
  signal out_available_min_s: free_vector(0 to dut_count_c-1);
  signal out_available_s: available_vector(0 to dut_count_c-1);

  -- Plain fifo, instantiated the way a user that knows nothing about
  -- cancellation does. Its commit and rollback signals below go
  -- nowhere, the fifo ports keep their default value.
  signal plain_in_data_s, plain_out_data_s: word_t;
  signal plain_in_valid_s, plain_in_ready_s: std_ulogic;
  signal plain_in_commit_s, plain_in_rollback_s: std_ulogic;
  signal plain_out_valid_s, plain_out_ready_s: std_ulogic;
  signal plain_out_commit_s, plain_out_rollback_s: std_ulogic;
  signal plain_in_free_s, plain_out_available_min_s: free_t;
  signal plain_out_available_s: available_t;

  -- Both sides only update their handshake outputs on a rising edge,
  -- so what the peer signal holds on a falling edge tells whether the
  -- coming rising edge carries a beat.
  procedure handshake_wait(signal clock: in std_ulogic;
                           signal peer: in std_ulogic;
                           constant what: in string) is
  begin
    for i in 0 to timeout_c
    loop
      if peer = '1' then
        return;
      end if;
      wait until falling_edge(clock);
    end loop;

    log_fatal("Timeout waiting for " & what);
  end procedure;

  procedure settle(signal clock: in std_ulogic;
                   constant cycle_count: in integer := settle_cycle_count_c) is
  begin
    for i in 1 to cycle_count
    loop
      wait until falling_edge(clock);
    end loop;
  end procedure;

  -- Hands one word over, asserting commit or rollback on the very
  -- cycle the word is taken.
  procedure put(signal clock: in std_ulogic;
                signal ready: in std_ulogic;
                signal valid: out std_ulogic;
                signal data: out word_t;
                signal commit: out std_ulogic;
                signal rollback: out std_ulogic;
                constant value: in integer;
                constant do_commit: in boolean := false;
                constant do_rollback: in boolean := false) is
  begin
    valid <= '1';
    data <= std_ulogic_vector(to_unsigned(value, data_width_c));

    handshake_wait(clock, ready, "fifo to accept a word");

    commit <= to_logic(do_commit);
    rollback <= to_logic(do_rollback);

    wait until rising_edge(clock);
    wait until falling_edge(clock);

    valid <= '0';
    data <= (others => '-');
    commit <= '0';
    rollback <= '0';
  end procedure;

  -- Takes one word, asserting commit or rollback on the very cycle
  -- the word is taken.
  procedure get(signal clock: in std_ulogic;
                signal valid: in std_ulogic;
                signal data: in word_t;
                signal ready: out std_ulogic;
                signal commit: out std_ulogic;
                signal rollback: out std_ulogic;
                constant value: in integer;
                constant do_commit: in boolean := false;
                constant do_rollback: in boolean := false) is
  begin
    ready <= '1';

    handshake_wait(clock, valid, "fifo to hand a word over");

    assert_equal("fifo output word",
                 data, std_ulogic_vector(to_unsigned(value, data_width_c)),
                 failure);

    commit <= to_logic(do_commit);
    rollback <= to_logic(do_rollback);

    wait until rising_edge(clock);
    wait until falling_edge(clock);

    ready <= '0';
    commit <= '0';
    rollback <= '0';
  end procedure;

begin

  duts: for i in 0 to dut_count_c-1
  generate
    dut: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => data_width_c,
        word_count_c => word_count_c,
        clock_count_c => 1,
        in_cancellable_c => in_cancel_cfg_c(i),
        out_cancellable_c => out_cancel_cfg_c(i)
        )
      port map(
        reset_n_i => reset_n_s(0),
        clock_i => clock_s,

        in_data_i => in_data_s(i),
        in_valid_i => in_valid_s(i),
        in_ready_o => in_ready_s(i),
        in_commit_i => in_commit_s(i),
        in_rollback_i => in_rollback_s(i),
        in_free_o => in_free_s(i),

        out_data_o => out_data_s(i),
        out_valid_o => out_valid_s(i),
        out_ready_i => out_ready_s(i),
        out_commit_i => out_commit_s(i),
        out_rollback_i => out_rollback_s(i),
        out_available_min_o => out_available_min_s(i),
        out_available_o => out_available_s(i)
        );
  end generate;

  plain_dut: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => data_width_c,
      word_count_c => word_count_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_s(0),
      clock_i => clock_s,

      in_data_i => plain_in_data_s,
      in_valid_i => plain_in_valid_s,
      in_ready_o => plain_in_ready_s,
      in_free_o => plain_in_free_s,

      out_data_o => plain_out_data_s,
      out_valid_o => plain_out_valid_s,
      out_ready_i => plain_out_ready_s,
      out_available_min_o => plain_out_available_min_s,
      out_available_o => plain_out_available_s
      );

  counter_monitor: process(clock_s(0)) is
  begin
    if rising_edge(clock_s(0)) then
      if reset_n_s(0) = '1' then
        for i in 0 to dut_count_c-1
        loop
          if out_available_s(i) > word_count_c then
            log_fatal("Fifo announces more words than it can hold");
          end if;

          if out_available_min_s(i) > out_available_s(i) then
            log_fatal("Fifo announces more words for sure than at most");
          end if;
        end loop;
      end if;
    end if;
  end process;

  stim: process is
  begin
    done_s <= "0";

    in_valid_s <= (others => '0');
    in_commit_s <= (others => '0');
    in_rollback_s <= (others => '0');
    out_ready_s <= (others => '0');
    out_commit_s <= (others => '0');
    out_rollback_s <= (others => '0');
    plain_in_valid_s <= '0';
    plain_in_commit_s <= '0';
    plain_in_rollback_s <= '0';
    plain_out_ready_s <= '0';
    plain_out_commit_s <= '0';
    plain_out_rollback_s <= '0';

    wait until reset_n_s(0) = '1';
    wait until falling_edge(clock_s(0));

    -- Uncommitted words take room, but never reach the output side.
    for i in 0 to 3
    loop
      put(clock_s(0), in_ready_s(both_c), in_valid_s(both_c), in_data_s(both_c),
          in_commit_s(both_c), in_rollback_s(both_c),
          16#40# + i);
    end loop;

    settle(clock_s(0));
    assert_equal("free space with 4 speculative words",
                 in_free_s(both_c), word_count_c - 4, failure);
    assert_equal("available with 4 speculative words",
                 out_available_s(both_c), 0, failure);
    assert_equal("output idle with 4 speculative words",
                 out_valid_s(both_c), '0', failure);

    -- Rollback takes the word of its own cycle back along with the
    -- ones before it.
    put(clock_s(0), in_ready_s(both_c), in_valid_s(both_c), in_data_s(both_c),
        in_commit_s(both_c), in_rollback_s(both_c),
        16#44#, do_rollback => true);

    settle(clock_s(0));
    assert_equal("free space after input rollback",
                 in_free_s(both_c), word_count_c, failure);
    assert_equal("available after input rollback",
                 out_available_s(both_c), 0, failure);
    assert_equal("output idle after input rollback",
                 out_valid_s(both_c), '0', failure);

    -- Commit on the last beat of a packet takes that beat in.
    for i in 0 to 7
    loop
      put(clock_s(0), in_ready_s(both_c), in_valid_s(both_c), in_data_s(both_c),
          in_commit_s(both_c), in_rollback_s(both_c),
          16#10# + i, do_commit => i = 7);
    end loop;

    settle(clock_s(0));
    assert_equal("available after input commit",
                 out_available_s(both_c), 8, failure);

    for i in 0 to 7
    loop
      get(clock_s(0), out_valid_s(both_c), out_data_s(both_c), out_ready_s(both_c),
          out_commit_s(both_c), out_rollback_s(both_c),
          16#10# + i, do_commit => i = 7);
    end loop;

    settle(clock_s(0));
    assert_equal("committed packet came out once",
                 out_valid_s(both_c), '0', failure);
    assert_equal("available after packet was read",
                 out_available_s(both_c), 0, failure);
    assert_equal("free space after packet was read",
                 in_free_s(both_c), word_count_c, failure);

    -- Words taken from the output port replay from the committed
    -- position, the word of the rollback cycle included.
    for i in 0 to 7
    loop
      put(clock_s(0), in_ready_s(both_c), in_valid_s(both_c), in_data_s(both_c),
          in_commit_s(both_c), in_rollback_s(both_c),
          16#20# + i, do_commit => i = 7);
    end loop;

    settle(clock_s(0));

    for i in 0 to 2
    loop
      get(clock_s(0), out_valid_s(both_c), out_data_s(both_c), out_ready_s(both_c),
          out_commit_s(both_c), out_rollback_s(both_c),
          16#20# + i);
    end loop;

    -- Words are still allocated as long as the reader did not commit.
    assert_equal("free space with 3 speculative reads",
                 in_free_s(both_c), word_count_c - 8, failure);

    get(clock_s(0), out_valid_s(both_c), out_data_s(both_c), out_ready_s(both_c),
        out_commit_s(both_c), out_rollback_s(both_c),
        16#23#, do_rollback => true);

    settle(clock_s(0));
    assert_equal("available after output rollback",
                 out_available_s(both_c), 8, failure);

    for i in 0 to 7
    loop
      get(clock_s(0), out_valid_s(both_c), out_data_s(both_c), out_ready_s(both_c),
          out_commit_s(both_c), out_rollback_s(both_c),
          16#20# + i, do_commit => i = 7);
    end loop;

    settle(clock_s(0));
    assert_equal("free space after output commit",
                 in_free_s(both_c), word_count_c, failure);

    -- Whole capacity is usable once both sides committed.
    for i in 0 to word_count_c-1
    loop
      put(clock_s(0), in_ready_s(both_c), in_valid_s(both_c), in_data_s(both_c),
          in_commit_s(both_c), in_rollback_s(both_c),
          16#80# + i, do_commit => i = word_count_c-1);
    end loop;

    settle(clock_s(0));
    assert_equal("free space when full", in_free_s(both_c), 0, failure);
    assert_equal("input stalls when full", in_ready_s(both_c), '0', failure);
    assert_equal("available when full", out_available_s(both_c), word_count_c, failure);

    for i in 0 to word_count_c-1
    loop
      get(clock_s(0), out_valid_s(both_c), out_data_s(both_c), out_ready_s(both_c),
          out_commit_s(both_c), out_rollback_s(both_c),
          16#80# + i, do_commit => i = word_count_c-1);
    end loop;

    settle(clock_s(0));
    assert_equal("free space when drained", in_free_s(both_c), word_count_c, failure);
    assert_equal("available when drained", out_available_s(both_c), 0, failure);

    -- Input side alone is cancellable: output commit is ignored, every
    -- word taken is gone for good.
    for i in 0 to 3
    loop
      put(clock_s(0), in_ready_s(in_side_c), in_valid_s(in_side_c), in_data_s(in_side_c),
          in_commit_s(in_side_c), in_rollback_s(in_side_c),
          16#50# + i);
    end loop;

    put(clock_s(0), in_ready_s(in_side_c), in_valid_s(in_side_c), in_data_s(in_side_c),
        in_commit_s(in_side_c), in_rollback_s(in_side_c),
        16#54#, do_rollback => true);

    settle(clock_s(0));
    assert_equal("output idle after input rollback",
                 out_valid_s(in_side_c), '0', failure);

    for i in 0 to 3
    loop
      put(clock_s(0), in_ready_s(in_side_c), in_valid_s(in_side_c), in_data_s(in_side_c),
          in_commit_s(in_side_c), in_rollback_s(in_side_c),
          16#60# + i, do_commit => i = 3);
    end loop;

    for i in 0 to 3
    loop
      get(clock_s(0), out_valid_s(in_side_c), out_data_s(in_side_c), out_ready_s(in_side_c),
          out_commit_s(in_side_c), out_rollback_s(in_side_c),
          16#60# + i);
    end loop;

    settle(clock_s(0));
    assert_equal("non cancellable output frees on its own",
                 in_free_s(in_side_c), word_count_c, failure);
    assert_equal("nothing left on non cancellable output",
                 out_valid_s(in_side_c), '0', failure);

    -- Output side alone is cancellable: input rollback is ignored,
    -- every word given is in for good.
    for i in 0 to 3
    loop
      put(clock_s(0), in_ready_s(out_side_c), in_valid_s(out_side_c), in_data_s(out_side_c),
          in_commit_s(out_side_c), in_rollback_s(out_side_c),
          16#70# + i, do_rollback => i = 3);
    end loop;

    settle(clock_s(0));
    assert_equal("non cancellable input commits on its own",
                 out_available_s(out_side_c), 4, failure);

    for i in 0 to 1
    loop
      get(clock_s(0), out_valid_s(out_side_c), out_data_s(out_side_c), out_ready_s(out_side_c),
          out_commit_s(out_side_c), out_rollback_s(out_side_c),
          16#70# + i);
    end loop;

    get(clock_s(0), out_valid_s(out_side_c), out_data_s(out_side_c), out_ready_s(out_side_c),
        out_commit_s(out_side_c), out_rollback_s(out_side_c),
        16#72#, do_rollback => true);

    settle(clock_s(0));

    for i in 0 to 3
    loop
      get(clock_s(0), out_valid_s(out_side_c), out_data_s(out_side_c), out_ready_s(out_side_c),
          out_commit_s(out_side_c), out_rollback_s(out_side_c),
          16#70# + i, do_commit => i = 3);
    end loop;

    settle(clock_s(0));
    assert_equal("free space after output commit",
                 in_free_s(out_side_c), word_count_c, failure);

    -- Fifo left at its default generics behaves as a plain fifo.
    for i in 0 to word_count_c-1
    loop
      put(clock_s(0), plain_in_ready_s, plain_in_valid_s, plain_in_data_s,
          plain_in_commit_s, plain_in_rollback_s,
          16#30# + i);
    end loop;

    settle(clock_s(0));
    assert_equal("plain fifo is full", plain_in_free_s, 0, failure);
    assert_equal("plain fifo holds all words",
                 plain_out_available_s, word_count_c, failure);

    for i in 0 to word_count_c-1
    loop
      get(clock_s(0), plain_out_valid_s, plain_out_data_s, plain_out_ready_s,
          plain_out_commit_s, plain_out_rollback_s,
          16#30# + i);
    end loop;

    settle(clock_s(0));
    assert_equal("plain fifo is empty", plain_out_available_s, 0, failure);
    assert_equal("plain fifo is free", plain_in_free_s, word_count_c, failure);

    done_s <= "1";
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 25 ns,
      reset_n_o(0) => reset_n_s(0),
      clock_o => clock_s,
      done_i => done_s
      );

end;
