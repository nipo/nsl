library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;

entity simulation_driver is
  generic (
    clock_count : natural;
    reset_count : natural;
    done_count : natural
    );
  port (
    clock_period : in nsl_simulation.driver.time_vector(0 to clock_count-1);
    reset_duration : in nsl_simulation.driver.time_vector(0 to reset_count-1);
    reset_n_o : out std_ulogic_vector(0 to reset_count-1);
    clock_o   : out std_ulogic_vector(0 to clock_count-1);
    done_i : in std_ulogic_vector(0 to done_count-1)
    );
end entity;

architecture beh of simulation_driver is
  constant context : log_context := "simdrv";
  signal all_done : boolean;
  signal clock : std_ulogic_vector(0 to clock_count-1);
begin

  all_done <= done_i = (done_i'range => '1');

  done: process(all_done)
  begin
    if all_done then
      log_info(context, "all done, terminating");
      terminate(0);
    end if;
  end process;
  
  resets: for i in 0 to reset_count-1
  generate
    resetter: process
    begin
      reset_n_o(i) <= '0';
      wait for reset_duration(i);
      reset_n_o(i) <= '1';
      wait;
    end process;
  end generate;

  dones: for i in 0 to done_count-1
  generate
    gen: process
    begin
      wait until done_i(i) = '1';
      log_info(context, "Done #" & integer'image(i) & " OK");
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

      log_info(context, "clock #" & integer'image(i) & " stopped");
      wait;
    end process;
  end generate;

  clock_o <= clock;
  
end architecture;
