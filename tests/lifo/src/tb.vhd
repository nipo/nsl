library ieee, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end tb;

library nsl_memory, nsl_simulation;
use nsl_memory.lifo.all;

architecture arch of tb is

  constant width : integer := 8;
  subtype word_t is std_ulogic_vector(width-1 downto 0);

  signal clock : std_ulogic;
  signal reset_n : std_ulogic;
  signal done : std_ulogic_vector(0 to 0);

  signal data_o, data_i : std_ulogic_vector(7 downto 0);
  signal op : lifo_op_t;
  signal empty, full: std_ulogic;

  procedure pause(signal clock : in std_ulogic) is
  begin
    wait until rising_edge(clock);
    wait until falling_edge(clock);
  end procedure;

  procedure data_push(signal clock : in std_ulogic;
                      signal op : out lifo_op_t;
                      signal data : out word_t;
                      constant wdata : in word_t) is
  begin
    op <= LIFO_OP_PUSH;
    data <= wdata;

    wait until rising_edge(clock);
    wait until falling_edge(clock);
    op <= LIFO_OP_IDLE;
    data <= (others => '-');
  end procedure;

  procedure data_pop(signal clock : in std_ulogic;
                     signal op : out lifo_op_t;
                     signal data : in word_t;
                     constant rdata : in word_t) is
  begin
    op <= LIFO_OP_POP;
    wait until rising_edge(clock);
    nsl_simulation.assertions.assert_equal("Popped data", rdata, data, error);
    wait until falling_edge(clock);
    op <= LIFO_OP_IDLE;
  end procedure;

begin

  lifo: nsl_memory.lifo.lifo_ram
    generic map(
      data_width_c => width,
      word_count_c => 16
      )
    port map(
      reset_n_i => reset_n,

      clock_i => clock,

      op_i => op,
      data_i => data_i,
      data_o => data_o,

      empty_o => empty,
      full_o => full
      );

  io_gen: process
    variable i : unsigned(word_t'range);
  begin
    op <= LIFO_OP_IDLE;
    data_i <= (others => '-');

    i := to_unsigned(0, i'length);
    
    wait until reset_n = '1';
    wait until falling_edge(clock);

    for ctr in 0 to 15
    loop
      data_push(clock, op, data_i, word_t(i));
      i := i + 1;
    end loop;

    pause(clock);
    
    for ctr in 0 to 15
    loop
      i := i - 1;
      pause(clock);
      data_pop(clock, op, data_o, word_t(i));
    end loop;

    i := to_unsigned(16, i'length);
    
    for ctr in 0 to 15
    loop
      data_push(clock, op, data_i, word_t(i));
      i := i + 1;
    end loop;

    for ctr in 0 to 15
    loop
      i := i - 1;
      data_pop(clock, op, data_o, word_t(i));
    end loop;

    i := to_unsigned(32, i'length);
    
    for ctr in 0 to 15
    loop
      data_push(clock, op, data_i, word_t(i));
      data_pop(clock, op, data_o, word_t(i));
      i := i + 1;
    end loop;

    i := to_unsigned(48, i'length);
    
    for ctr in 0 to 15
    loop
      data_push(clock, op, data_i, word_t(i));
      pause(clock);
      data_pop(clock, op, data_o, word_t(i));
      i := i + 1;
    end loop;

    i := to_unsigned(64, i'length);
    
    for ctr in 0 to 15
    loop
      data_push(clock, op, data_i, word_t(i));
      pause(clock);
      data_pop(clock, op, data_o, word_t(i));
      pause(clock);
      i := i + 1;
    end loop;

    i := to_unsigned(80, i'length);
    
    for ctr in 0 to 15
    loop
      pause(clock);
      data_push(clock, op, data_i, word_t(i));
      data_pop(clock, op, data_o, word_t(i));
      pause(clock);
      i := i + 1;
    end loop;

    done(0) <= '1';

    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 12 ns,
      reset_n_o(0) => reset_n,
      clock_o(0) => clock,
      done_i => done
      );

end;
