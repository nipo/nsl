library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;

entity simulation_driver is
  generic (
    clock_count : natural;
    reset_time : time;
    done_count : natural
    );
  port (
    clock_period : in nsl_simulation.driver.time_vector(0 to clock_count);
    reset_n_o : out std_ulogic;
    clock_o   : out std_ulogic_vector(0 to clock_count);
    done_i : in std_ulogic_vector(0 to done_count-1)
    );
end entity;

architecture beh of simulation_driver is
  signal all_done : boolean;
  signal clock : std_ulogic_vector(0 to clock_count);
begin

  all_done <= done_i = (done_i'range => '1');

  done: process(all_done)
  begin
    if all_done then
      assert false
        report "all done, SUCCESS"
        severity failure;
    end if;
  end process;
  
  resetter: process
  begin
    reset_n_o <= '0';
    wait for reset_time;
    reset_n_o <= '1';
    wait;
  end process;

  dones: for i in 0 to done_count-1
  generate
    gen: process
    begin
      wait until done_i(i) = '1';
      assert false report "Done #" & integer'image(i) & " OK" severity note;
      wait;
    end process;
  end generate;

  clocks: for i in 0 to clock_count-1
  generate
    gen: process
      variable half_period : time;
    begin
      while not all_done loop
        -- Update half period once per cycle on purpose
        half_period := clock_period(i) / 2;

        clock(i) <= '1';
        wait for half_period;
        clock(i) <= '0';
        wait for half_period;
      end loop;

      assert false report "clock " & integer'image(i) & " stopped" severity note;
      wait;
    end process;
  end generate;

  clock_o <= clock;
  
end architecture;
