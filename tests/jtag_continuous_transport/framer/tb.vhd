library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_clocking, nsl_data, nsl_simulation;
use nsl_jtag.continuous_transport.all;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Unit test for the continuous_transport TX framer. A 5-byte packet is offered
-- on the TX FIFO read side, a generous budget is granted, and the emitted byte
-- stream is captured. It must contain a single data frame (header 0x44 = 5
-- bytes, last) carrying the packet, surrounded by credit-refresh filler.
entity tb is
end entity;

architecture arch of tb is

  constant payload_c : byte_string := from_hex("deadbeef11");
  constant rx_free_c : unsigned(15 downto 0) := x"0014"; -- advertise 20
  constant tx_level_c : unsigned(15 downto 0) := x"0007"; -- backlog non-empty

  signal clock         : std_ulogic := '0';
  signal reset_n_async : std_ulogic := '0';
  signal reset_n       : std_ulogic;

  signal capture    : std_ulogic := '0';
  signal byte_ready : std_ulogic := '0';
  signal byte_out   : byte;

  signal budget_set : std_ulogic := '0';
  signal budget     : unsigned(15 downto 0) := (others => '0');

  signal tx_data  : byte;
  signal tx_last  : std_ulogic;
  signal tx_valid : std_ulogic;
  signal tx_ready : std_ulogic;

  signal done   : std_ulogic := '0';
  signal tx_idx : natural := 0;

  signal captured : byte_string(0 to 63);
  signal cap_n    : natural := 0;

begin

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock,
      data_i => reset_n_async,
      data_o => reset_n
      );

  dut: nsl_jtag.continuous_transport.continuous_transport_framer
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      capture_i => capture,
      byte_ready_i => byte_ready,
      byte_o => byte_out,
      budget_set_i => budget_set,
      budget_i => budget,
      tx_data_i => tx_data,
      tx_last_i => tx_last,
      tx_valid_i => tx_valid,
      tx_ready_o => tx_ready,
      rx_free_i => rx_free_c,
      tx_level_i => tx_level_c
      );

  -- TX FIFO source model.
  tx_data <= payload_c(payload_c'left + tx_idx) when tx_idx < payload_c'length
             else x"00";
  tx_valid <= '1' when tx_idx < payload_c'length else '0';
  tx_last <= '1' when tx_idx = payload_c'length - 1 else '0';

  tx_pop: process(clock, reset_n)
  begin
    if reset_n = '0' then
      tx_idx <= 0;
    elsif rising_edge(clock) then
      if tx_valid = '1' and tx_ready = '1' and tx_idx < payload_c'length then
        tx_idx <= tx_idx + 1;
      end if;
    end if;
  end process;

  -- Capture each emitted byte.
  capture_bytes: process(clock, reset_n)
  begin
    if reset_n = '0' then
      cap_n <= 0;
    elsif rising_edge(clock) then
      if byte_ready = '1' and cap_n < 64 then
        captured(cap_n) <= byte_out;
        cap_n <= cap_n + 1;
      end if;
    end if;
  end process;

  stim: process
    variable found : boolean := false;
    variable credit_seen : boolean := false;
  begin
    wait for 50 ns;
    wait until rising_edge(clock);
    wait until rising_edge(clock);

    for i in 0 to 64 loop
      wait until rising_edge(clock);
    end loop;

    -- Batch start, then grant a generous budget.
    capture <= '1';
    wait until rising_edge(clock);
    capture <= '0';
    budget_set <= '1';
    budget <= to_unsigned(100, 16);
    wait until rising_edge(clock);
    budget_set <= '0';

    -- Emit one byte per cycle for a while.
    byte_ready <= '1';
    for i in 0 to 39 loop
      wait until rising_edge(clock);
    end loop;
    byte_ready <= '0';
    wait until rising_edge(clock);

    -- Find the data frame: header 0x44 then the 5 payload bytes.
    for p in 0 to cap_n - 1 - payload_c'length loop
      if captured(p to p + payload_c'length) = from_hex("44") & payload_c then
        found := true;
      end if;
    end loop;

    assert found
      report "data frame (0x44 + deadbeef11) not found in emitted stream"
      severity failure;
    -- A credit refresh (0xf1) must appear as filler somewhere (the sender
    -- returns to one after the data frame; whether it leads or trails the
    -- data depends on when the chunk becomes ready).
    for p in 0 to cap_n - 1 loop
      if captured(p) = ctl_credit_c then
        credit_seen := true;
      end if;
    end loop;
    assert credit_seen
      report "no credit refresh emitted" severity failure;

    log_info("continuous_transport framer OK");
    done <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 5 ns,
      reset_duration(0) => 50 ns,
      reset_n_o(0) => reset_n_async,
      clock_o(0) => clock,
      done_i(0) => done
      );

end architecture;
