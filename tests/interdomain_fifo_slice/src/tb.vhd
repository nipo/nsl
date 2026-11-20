library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_simulation;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;

-- Counting words through interdomain_fifo_slice, from a slow to a fast
-- clock, from a fast to a slow clock, and between clocks of nearly the
-- same rate, with stalls on both sides: every word must come out once,
-- in order.
entity tb is
end tb;

architecture arch of tb is

  constant word_count_c : natural := 300;
  constant pair_count_c : natural := 3;

  type period_vector is array(natural range <>) of time;
  -- Input and output clock periods, per pair.
  constant in_period_c : period_vector(0 to pair_count_c-1) := (20 ns, 8 ns, 8 ns);
  constant out_period_c : period_vector(0 to pair_count_c-1) := (8 ns, 20 ns, 8.01 ns);

  signal done_s : std_ulogic_vector(0 to pair_count_c-1) := (others => '0');
  signal reset_n_s : std_ulogic := '0';

begin

  reset_n_s <= '1' after 200 ns;

  pairs: for p in 0 to pair_count_c-1
  generate
    signal in_clock_s, out_clock_s : std_ulogic := '0';
    signal in_data_s, out_data_s : std_ulogic_vector(15 downto 0);
    signal in_valid_s, in_ready_s, out_valid_s, out_ready_s : std_ulogic;
  begin

    in_clock_s <= not in_clock_s after in_period_c(p) / 2 when done_s(p) = '0';
    out_clock_s <= not out_clock_s after out_period_c(p) / 2 when done_s(p) = '0';

    dut: nsl_clocking.interdomain.interdomain_fifo_slice
      generic map(
        data_width_c => 16
        )
      port map(
        reset_n_i => reset_n_s,
        clock_i(0) => in_clock_s,
        clock_i(1) => out_clock_s,
        out_data_o => out_data_s,
        out_ready_i => out_ready_s,
        out_valid_o => out_valid_s,
        in_data_i => in_data_s,
        in_valid_i => in_valid_s,
        in_ready_o => in_ready_s
        );

    writer: process
      variable n, cycle : natural := 0;
    begin
      in_valid_s <= '0';
      in_data_s <= (others => '0');
      wait until reset_n_s = '1';
      while n < word_count_c
      loop
        wait until rising_edge(in_clock_s);
        if in_valid_s = '1' and in_ready_s = '1' then
          n := n + 1;
        end if;
        in_data_s <= std_ulogic_vector(to_unsigned(n * 977 mod 65536, 16));
        cycle := cycle + 1;
        -- Stalls one cycle in 7.
        if n < word_count_c and cycle mod 7 /= 3 then
          in_valid_s <= '1';
        else
          in_valid_s <= '0';
        end if;
      end loop;
      in_valid_s <= '0';
      wait;
    end process;

    reader: process
      variable n, cycle : natural := 0;
    begin
      out_ready_s <= '0';
      wait until reset_n_s = '1';
      while n < word_count_c
      loop
        wait until rising_edge(out_clock_s);
        if out_valid_s = '1' and out_ready_s = '1' then
          assert out_data_s = std_ulogic_vector(to_unsigned(n * 977 mod 65536, 16))
            report "pair " & integer'image(p) & ": word " & integer'image(n) & " wrong"
            severity failure;
          n := n + 1;
        end if;
        cycle := cycle + 1;
        -- Stalls two cycles in 11.
        if cycle mod 11 < 2 then
          out_ready_s <= '0';
        else
          out_ready_s <= '1';
        end if;
      end loop;
      for i in 0 to 20
      loop
        wait until rising_edge(out_clock_s);
        assert out_valid_s = '0'
          report "pair " & integer'image(p) & ": extra word" severity failure;
      end loop;
      log_info("pair " & integer'image(p) & ": " & integer'image(word_count_c) & " words in order");
      done_s(p) <= '1';
      wait;
    end process;

  end generate;

  finish: process
  begin
    wait until done_s = (done_s'range => '1');
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process
  begin
    wait for 1 ms;
    assert false report "Timeout" severity failure;
    wait;
  end process;

end architecture;
