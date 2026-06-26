library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_clocking, nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Unit test for the continuous_transport receive deframer: a hand-built byte
-- stream (credit, set-pad, two data frames, idle) is pushed in, and the
-- decoded payload, last flags, budget grant and pad are checked.
entity tb is
end entity;

architecture arch of tb is

  signal clock         : std_ulogic := '0';
  signal reset_n_async : std_ulogic := '0';
  signal reset_n       : std_ulogic;

  signal byte_value       : byte := (others => '0');
  signal byte_valid : std_ulogic := '0';

  signal rx_data  : byte;
  signal rx_last  : std_ulogic;
  signal rx_valid : std_ulogic;
  signal budget     : unsigned(15 downto 0);
  signal budget_set : std_ulogic;
  signal pad        : std_ulogic_vector(2 downto 0);
  signal pad_set    : std_ulogic;

  signal done : std_ulogic := '0';

  signal rx_buf      : byte_string(0 to 15);
  signal rx_last_buf : std_ulogic_vector(0 to 15) := (others => '0');
  signal rx_n        : natural := 0;
  signal budget_seen : natural := 0;
  signal last_budget : unsigned(15 downto 0) := (others => '0');
  signal pad_seen    : natural := 0;
  signal last_pad    : std_ulogic_vector(2 downto 0) := (others => '0');

begin

  reset_sync: nsl_clocking.async.async_edge
    port map(clock_i => clock, data_i => reset_n_async, data_o => reset_n);

  dut: nsl_jtag.continuous_transport.continuous_transport_deframer
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      byte_i => byte_value,
      byte_valid_i => byte_valid,
      rx_data_o => rx_data,
      rx_last_o => rx_last,
      rx_valid_o => rx_valid,
      budget_o => budget,
      budget_set_o => budget_set,
      pad_o => pad,
      pad_set_o => pad_set
      );

  collect: process(clock, reset_n)
  begin
    if reset_n = '0' then
      rx_n <= 0;
      budget_seen <= 0;
      pad_seen <= 0;
    elsif rising_edge(clock) then
      if rx_valid = '1' then
        rx_buf(rx_n) <= rx_data;
        rx_last_buf(rx_n) <= rx_last;
        rx_n <= rx_n + 1;
      end if;
      if budget_set = '1' then
        last_budget <= budget;
        budget_seen <= budget_seen + 1;
      end if;
      if pad_set = '1' then
        last_pad <= pad;
        pad_seen <= pad_seen + 1;
      end if;
    end if;
  end process;

  stim: process
    procedure send(b : byte) is
    begin
      wait until rising_edge(clock);
      byte_value <= b;
      byte_valid <= '1';
      wait until rising_edge(clock);
      byte_valid <= '0';
    end procedure;
  begin
    wait for 50 ns;
    wait until rising_edge(clock);
    wait until rising_edge(clock);

    -- Credit = 16 (LE: 0x10, 0x00)
    send(x"f1"); send(x"10"); send(x"00");
    -- Set TDO pad = 3
    send(x"fb");
    -- Data frame, 4 bytes, not last
    send(x"03"); send(x"aa"); send(x"bb"); send(x"cc"); send(x"dd");
    -- Data frame, 2 bytes, last
    send(x"41"); send(x"ee"); send(x"ff");
    -- Idle
    send(x"f0");

    for i in 0 to 7 loop
      wait until rising_edge(clock);
    end loop;

    assert rx_n = 6 report "expected 6 payload bytes, got " & integer'image(rx_n) severity failure;
    assert_equal("deframer", "d0", rx_buf(0), x"aa", failure);
    assert_equal("deframer", "d1", rx_buf(1), x"bb", failure);
    assert_equal("deframer", "d2", rx_buf(2), x"cc", failure);
    assert_equal("deframer", "d3", rx_buf(3), x"dd", failure);
    assert_equal("deframer", "d4", rx_buf(4), x"ee", failure);
    assert_equal("deframer", "d5", rx_buf(5), x"ff", failure);
    assert rx_last_buf(0 to 4) = "00000" report "unexpected early last" severity failure;
    assert rx_last_buf(5) = '1' report "missing last on final byte" severity failure;

    assert budget_seen = 1 report "expected one credit" severity failure;
    assert_equal("deframer", "budget", std_ulogic_vector(last_budget), x"0010", failure);
    assert pad_seen = 1 report "expected one pad update" severity failure;
    assert_equal("deframer", "pad", last_pad, "011", failure);

    log_info("continuous_transport deframer OK");
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
