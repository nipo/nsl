library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;

-- Outputs are generated from the solved mapping, not from the
-- requested rates: a request granted some tolerance yields the same
-- approximated rates the hardware realization would.  Output rates
-- are ideal, no jitter is modeled; lock is granted after some input
-- clock activity out of reset.
entity pll_multi is
  generic(
    config_c : pll_config_t
    );
  port(
    clock_i : in std_ulogic;
    clock_o : out std_ulogic_vector(0 to config_c.output_count-1);

    reset_n_i : in std_ulogic;
    locked_o : out std_ulogic
    );
end entity;

architecture sim of pll_multi is

  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);
  constant lock_cycles_c : integer := 100;

  signal started_s : boolean := false;

begin


  log: process
  begin
    report "Simulation PLL: " & to_string(mapping_c)
      severity note;
    wait;
  end process;

  lock: process
  begin
    started_s <= false;
    locked_o <= '0';
    if reset_n_i /= '1' then
      wait until reset_n_i = '1';
    end if;
    input_wait: for i in 0 to lock_cycles_c - 1 loop
      wait until rising_edge(clock_i) or reset_n_i = '0';
      if reset_n_i /= '1' then
        exit input_wait;
      end if;
    end loop;
    if reset_n_i = '1' then
      started_s <= true;
      locked_o <= '1';
      wait until reset_n_i /= '1';
    end if;
  end process;

  outputs: for i in 0 to config_c.output_count - 1 generate
    constant hz_c : real := mapping_output_hz(mapping_c, i);
    constant period_c : time := (1.0e9 / hz_c) * 1 ns;
    constant offset_c : time := (period_c * mapping_c.output(i).phase.num)
                                / mapping_c.output(i).phase.den;
  begin
    gen: process
    begin
      clock_o(i) <= '0';
      if not started_s then
        wait until started_s;
      end if;
      wait for offset_c;
      while started_s loop
        clock_o(i) <= '1';
        wait for period_c / 2;
        clock_o(i) <= '0';
        wait for period_c - period_c / 2;
      end loop;
    end process;
  end generate;

end architecture sim;
