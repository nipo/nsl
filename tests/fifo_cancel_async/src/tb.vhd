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
  -- Words the input side hands over, committing every in_packet_size_c
  -- of them.
  constant total_word_count_c: integer := 32;
  constant in_packet_size_c: integer := 8;
  -- Words the output side takes before committing. Holding a whole
  -- capacity worth of them uncommitted keeps the input side from
  -- overwriting anything a rollback would have to replay.
  constant out_packet_size_c: integer := word_count_c;
  -- Value of the words the input side takes back right away.
  constant junk_value_c: integer := 16#ee#;
  -- Cycles a handshake may be waited for before the testbench gives up.
  constant timeout_c: integer := 1000;
  -- Cycles left for the position crossings to settle before a counter
  -- is looked at. Crossing a commit takes one cycle per word.
  constant settle_cycle_count_c: integer := 128;

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector is array(natural range <>) of word_t;

  subtype free_t is integer range 0 to word_count_c;
  type free_vector is array(natural range <>) of free_t;
  subtype available_t is integer range 0 to word_count_c+1;
  type available_vector is array(natural range <>) of available_t;

  type boolean_vector is array(natural range <>) of boolean;

  -- One fifo per side combination.
  constant both_c: natural := 0;
  constant in_side_c: natural := 1;
  constant out_side_c: natural := 2;
  constant plain_c: natural := 3;
  constant dut_count_c: natural := 4;

  constant in_cancel_cfg_c: boolean_vector(0 to dut_count_c-1)
    := (both_c => true, in_side_c => true,
        out_side_c => false, plain_c => false);
  constant out_cancel_cfg_c: boolean_vector(0 to dut_count_c-1)
    := (both_c => true, in_side_c => false,
        out_side_c => true, plain_c => false);

  -- Value of the word at a given position in the committed stream.
  function word_value(index: natural) return integer is
  begin
    return (index * 5 + 1) mod 256;
  end function;

  signal clock_s: std_ulogic_vector(0 to 1);
  signal reset_n_s: std_ulogic_vector(0 to 0);
  -- One bit per side of each fifo, input sides first.
  signal done_s: std_ulogic_vector(0 to 2*dut_count_c-1);

  signal in_data_s, out_data_s: word_vector(0 to dut_count_c-1);
  signal in_valid_s, in_ready_s: std_ulogic_vector(0 to dut_count_c-1);
  signal in_commit_s, in_rollback_s: std_ulogic_vector(0 to dut_count_c-1);
  signal out_valid_s, out_ready_s: std_ulogic_vector(0 to dut_count_c-1);
  signal out_commit_s, out_rollback_s: std_ulogic_vector(0 to dut_count_c-1);
  signal in_free_s: free_vector(0 to dut_count_c-1);
  signal out_available_min_s: free_vector(0 to dut_count_c-1);
  signal out_available_s: available_vector(0 to dut_count_c-1);

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
        clock_count_c => 2,
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

    -- Input side hands packets over, taking a junk packet back first
    -- when it may. Commit lands on the last beat of every packet.
    in_side: process is
    begin
      done_s(i) <= '0';
      in_valid_s(i) <= '0';
      in_commit_s(i) <= '0';
      in_rollback_s(i) <= '0';

      wait until reset_n_s(0) = '1';
      wait until falling_edge(clock_s(0));

      if in_cancel_cfg_c(i) then
        for j in 0 to 2
        loop
          put(clock_s(0), in_ready_s(i), in_valid_s(i), in_data_s(i),
              in_commit_s(i), in_rollback_s(i),
              junk_value_c, do_rollback => j = 2);
        end loop;

        settle(clock_s(0));
        assert_equal("free space after input rollback",
                     in_free_s(i), word_count_c, failure);
      end if;

      for index in 0 to total_word_count_c-1
      loop
        put(clock_s(0), in_ready_s(i), in_valid_s(i), in_data_s(i),
            in_commit_s(i), in_rollback_s(i),
            word_value(index),
            do_commit => (index mod in_packet_size_c) = in_packet_size_c-1);
      end loop;

      wait until done_s(dut_count_c+i) = '1';
      settle(clock_s(0));

      assert_equal("free space once drained",
                   in_free_s(i), word_count_c, failure);

      done_s(i) <= '1';
      wait;
    end process;

    -- Output side takes the whole stream, taking a couple of words
    -- back on the way when it may.
    out_side: process is
      variable index_v, committed_v: natural;
      variable rollback_at_v: integer;
    begin
      done_s(dut_count_c+i) <= '0';
      out_ready_s(i) <= '0';
      out_commit_s(i) <= '0';
      out_rollback_s(i) <= '0';

      index_v := 0;
      committed_v := 0;
      if out_cancel_cfg_c(i) then
        rollback_at_v := 10;
      else
        rollback_at_v := -1;
      end if;

      wait until reset_n_s(0) = '1';
      wait until falling_edge(clock_s(1));

      while committed_v < total_word_count_c
      loop
        if index_v = rollback_at_v then
          get(clock_s(1), out_valid_s(i), out_data_s(i), out_ready_s(i),
              out_commit_s(i), out_rollback_s(i),
              word_value(index_v), do_rollback => true);

          -- Every word taken since the last commit comes again.
          index_v := committed_v;
          if rollback_at_v = 10 then
            rollback_at_v := 30;
          else
            rollback_at_v := -1;
          end if;
        elsif (index_v mod out_packet_size_c) = out_packet_size_c-1 then
          get(clock_s(1), out_valid_s(i), out_data_s(i), out_ready_s(i),
              out_commit_s(i), out_rollback_s(i),
              word_value(index_v), do_commit => true);

          index_v := index_v + 1;
          committed_v := index_v;
        else
          get(clock_s(1), out_valid_s(i), out_data_s(i), out_ready_s(i),
              out_commit_s(i), out_rollback_s(i),
              word_value(index_v));

          index_v := index_v + 1;
        end if;
      end loop;

      settle(clock_s(1));

      assert_equal("nothing left once drained",
                   out_valid_s(i), '0', failure);
      assert_equal("available once drained",
                   out_available_s(i), 0, failure);

      done_s(dut_count_c+i) <= '1';
      wait;
    end process;

    -- Fill counts may never exceed the fifo capacity, and the count
    -- that leaves the presented word out may never exceed the other.
    out_monitor: process(clock_s(1)) is
    begin
      if rising_edge(clock_s(1)) then
        if reset_n_s(0) = '1' then
          if out_available_s(i) > word_count_c then
            log_fatal("Fifo announces more words than it can hold");
          end if;

          if out_available_min_s(i) > out_available_s(i) then
            log_fatal("Fifo announces more words for sure than at most");
          end if;
        end if;
      end if;
    end process;
  end generate;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 13 ns,
      reset_duration(0) => 25 ns,
      reset_n_o(0) => reset_n_s(0),
      clock_o => clock_s,
      done_i => done_s
      );

end;
