library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_clocking, nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  constant clock_count_c : natural := 2;
  signal clock_s : std_ulogic_vector(0 to clock_count_c-1);
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  type side_t is
  record
    valid, ready: std_ulogic;
    count: unsigned(3 downto 0);
  end record;

  signal in_s, out_s: side_t;
  
begin

  in_test: process is
  begin
    done_s(0) <= '0';

    in_s.valid <= '0';

    wait for 100 ns;
    
    wait until rising_edge(clock_s(0));

    for i in 0 to 60
    loop
      put_one: loop
        in_s.valid <= '1';
        wait until falling_edge(clock_s(0));
        wait until rising_edge(clock_s(0));
        in_s.valid <= '0';
        if in_s.ready = '1' then
          exit put_one;
        end if;
      end loop;
    end loop;
    
    done_s(0) <= '1';
    wait;
  end process;

  out_test: process is
  begin
    done_s(1) <= '0';

    out_s.ready <= '0';

    wait for 150 ns;

    wait until rising_edge(clock_s(clock_count_c-1));

    for i in 0 to 60
    loop
      put_one: loop
        out_s.ready <= '1';
        wait until falling_edge(clock_s(clock_count_c-1));
        wait until rising_edge(clock_s(clock_count_c-1));
        out_s.ready <= '0';
        if out_s.valid = '1' then
          exit put_one;
        end if;
      end loop;
    end loop;

    wait for 100 ns;

    done_s(1) <= '1';
    wait;
  end process;
  
  fifo: nsl_memory.fifo.fifo_count
    generic map(
      max_count_l2_c => 4,
      clock_count_c => clock_s'length
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      out_ready_i => out_s.ready,
      out_valid_o => out_s.valid,
      out_counter_o => out_s.count,

      in_ready_o => in_s.ready,
      in_valid_i => in_s.valid,
      in_counter_o => in_s.count
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => clock_s'length,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 12 ns,
      reset_duration(0) => 12 ns,
      reset_n_o(0) => reset_n_s,
      clock_o => clock_s,
      done_i => done_s
      );
  
end;
