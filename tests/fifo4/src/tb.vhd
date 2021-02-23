library ieee, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end tb;

library nsl_memory, nsl_simulation;
use nsl_simulation.assertions.all;

architecture arch of tb is

  constant width : integer := 8;
  subtype word_t is std_ulogic_vector(width-1 downto 0);

  type half_period_t is
  record
    left, right, left_init, right_init: time;
  end record;
  
  type side_t is
  record
    clock, ready, valid, ready_after, valid_after : std_ulogic;
    commit, rollback : std_ulogic;
    data, data_after: word_t;
  end record;

  signal l, r : side_t;
  signal s_resetn_async, s_done : std_ulogic := '0';

  procedure data_put(signal clock : in std_ulogic;
                     signal ready : in std_ulogic;
                     signal valid : out std_ulogic;
                     signal data : out word_t;
                     constant wdata : in word_t) is
  begin
    valid <= '1';
    data <= wdata;

    wait until ready = '1' and rising_edge(clock);
    wait until falling_edge(clock);
    valid <= '0';
    data <= (others => '-');
  end procedure;

  procedure data_put(signal clock : in std_ulogic;
                     signal ready : in std_ulogic;
                     signal valid : out std_ulogic;
                     signal data : out word_t;
                     constant wdata : in integer) is
  begin
    data_put(clock, ready, valid, data, std_ulogic_vector(to_unsigned(wdata, data'length)));
  end procedure;

  procedure data_commit(signal clock : in std_ulogic;
                        signal commit : out std_ulogic) is
  begin
    commit <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    commit <= '0';
  end procedure;

  procedure data_rollback(signal clock : in std_ulogic;
                          signal rollback : out std_ulogic) is
  begin
    rollback <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    rollback <= '0';
  end procedure;
  
  procedure data_get(signal clock : in std_ulogic;
                     signal ready : out std_ulogic;
                     signal valid : in std_ulogic;
                     signal data : in word_t;
                     constant rdata : in word_t) is
    variable complaint : line;
  begin
    ready <= '1';

    wait until valid = '1' and rising_edge(clock);

    assert_equal("Expected value", rdata, data, error);

    wait until falling_edge(clock);
    ready <= '0';
  end procedure;
  
  procedure data_get(signal clock : in std_ulogic;
                     signal ready : out std_ulogic;
                     signal valid : in std_ulogic;
                     signal data : in word_t;
                     constant rdata : in integer) is
  begin
    data_get(clock, ready, valid, data, std_ulogic_vector(to_unsigned(rdata, data'length)));
  end procedure;

begin

  fifo: nsl_memory.fifo.fifo_cancellable
    generic map(
      data_width_c => width,
      word_count_l2_c => 6
      )
    port map(
      reset_n_i => s_resetn_async,

      clock_i => l.clock,

      in_data_i => l.data,
      in_valid_i => l.valid,
      in_ready_o => l.ready,
      in_commit_i => l.commit,
      in_rollback_i => l.rollback,

      out_data_o => r.data,
      out_ready_i => r.ready,
      out_valid_o => r.valid,
      out_commit_i => r.commit,
      out_rollback_i => r.rollback
      );

  input_gen: process
    variable iter: natural;
  begin
    l.valid <= '0';
    l.data <= (others => '-');
    l.commit <= '0';
    l.rollback <= '0';

    wait until s_resetn_async = '1';

    wait for 15 ns;
    wait until falling_edge(l.clock);

    for i in 0 to 31
    loop
      data_put(l.clock, l.ready_after, l.valid, l.data, i);
    end loop;

    data_commit(l.clock, l.commit);

    for i in 64 to 95
    loop
      data_put(l.clock, l.ready_after, l.valid, l.data, i);
    end loop;

    data_rollback(l.clock, l.rollback);

    for i in 32 to 79
    loop
      data_put(l.clock, l.ready_after, l.valid, l.data, i);
    end loop;

    data_commit(l.clock, l.commit);

    wait;
  end process;

  output_gen: process
    variable iter: natural;
  begin
    r.ready <= '0';
    s_done <= '0';
    r.commit <= '0';
    r.rollback <= '0';

    wait until s_resetn_async = '1';
    wait until falling_edge(r.clock);

    for i in 0 to 15
    loop
      data_get(r.clock, r.ready, r.valid_after, r.data_after, i);
    end loop;

    data_rollback(r.clock, r.rollback);

    wait for 600 ns;
    
    for i in 0 to 15
    loop
      data_get(r.clock, r.ready, r.valid_after, r.data_after, i);
    end loop;

    data_commit(r.clock, r.commit);

    for i in 16 to 79
    loop
      data_get(r.clock, r.ready, r.valid_after, r.data_after, i);
    end loop;

    data_commit(r.clock, r.commit);

    wait for 30 ns;
    s_done <= '1';
    wait;
  end process;

  reset_gen: process
    variable iter: natural;
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait;    
  end process;

  l.ready_after <= l.ready after 1 ns;
  l.valid_after <= l.valid after 1 ns;
  l.data_after <= l.data after 1 ns;
  r.ready_after <= r.ready after 1 ns;
  r.valid_after <= r.valid after 1 ns;
  r.data_after <= r.data after 1 ns;
  
  clock_gen: process
  begin
    l.clock <= '0';
    r.clock <= '0';

    while s_done = '0' loop
      l.clock <= '1';
      r.clock <= '1';
      wait for 5 ns;
      l.clock <= '0';
      r.clock <= '0';
      wait for 5 ns;
    end loop;

    wait;
  end process;

end;
