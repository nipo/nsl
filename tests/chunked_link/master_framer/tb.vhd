library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_clocking, nsl_data, nsl_simulation;
use nsl_bnoc.chunked_link.all;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Unit test for the chunked_link master framer. A 5-byte packet is offered on
-- the TX stream, a budget grant is requested, then the slave RX credit is set
-- twice: first low enough to force a partial data frame, then high enough for
-- the remainder. The emitted byte stream must contain the grant frame, a
-- 2-byte not-last data frame and a 3-byte last data frame, with idle filler in
-- between; credit values are derated by the flight margin before gating data.
entity tb is
end entity;

architecture arch of tb is

  constant payload_c : byte_string := from_hex("deadbeef11");
  constant margin_c : natural := 16;

  signal clock         : std_ulogic := '0';
  signal reset_n_async : std_ulogic := '0';
  signal reset_n       : std_ulogic;

  signal batch_start : std_ulogic := '0';
  signal byte_ready  : std_ulogic := '0';
  signal byte_out    : byte;

  signal credit_set : std_ulogic := '0';
  signal credit     : unsigned(15 downto 0) := (others => '0');

  signal grant       : unsigned(15 downto 0) := (others => '0');
  signal grant_valid : std_ulogic := '0';
  signal grant_ready : std_ulogic;
  signal grant_sent  : std_ulogic;

  signal tx_data  : byte;
  signal tx_last  : std_ulogic;
  signal tx_valid : std_ulogic;
  signal tx_ready : std_ulogic;

  signal done   : std_ulogic := '0';
  signal tx_idx : natural := 0;

  signal captured : byte_string(0 to 127);
  signal cap_n    : natural := 0;
  signal grant_sent_seen : natural := 0;

begin

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock,
      data_i => reset_n_async,
      data_o => reset_n
      );

  dut: nsl_bnoc.chunked_link.chunked_link_master_framer
    generic map(
      flight_margin_c => margin_c
      )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      batch_start_i => batch_start,
      byte_ready_i => byte_ready,
      byte_o => byte_out,
      credit_set_i => credit_set,
      credit_i => credit,
      grant_i => grant,
      grant_valid_i => grant_valid,
      grant_ready_o => grant_ready,
      grant_sent_o => grant_sent,
      tx_data_i => tx_data,
      tx_last_i => tx_last,
      tx_valid_i => tx_valid,
      tx_ready_o => tx_ready
      );

  -- TX stream source model.
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

  -- Capture each emitted byte and every grant emission.
  capture_bytes: process(clock, reset_n)
  begin
    if reset_n = '0' then
      cap_n <= 0;
      grant_sent_seen <= 0;
    elsif rising_edge(clock) then
      if byte_ready = '1' and cap_n < 128 then
        captured(cap_n) <= byte_out;
        cap_n <= cap_n + 1;
      end if;
      if grant_sent = '1' then
        grant_sent_seen <= grant_sent_seen + 1;
      end if;
    end if;
  end process;

  stim: process
    procedure find(pattern : byte_string; what : string) is
      variable found : boolean := false;
    begin
      for p in 0 to cap_n - pattern'length loop
        if captured(p to p + pattern'length - 1) = pattern then
          found := true;
        end if;
      end loop;
      assert found
        report what & " not found in emitted stream"
        severity failure;
    end procedure;
  begin
    wait for 50 ns;
    wait until falling_edge(clock);

    batch_start <= '1';
    wait until falling_edge(clock);
    batch_start <= '0';

    byte_ready <= '1';

    -- Request a budget grant of 0x0123.
    grant <= x"0123";
    grant_valid <= '1';
    wait until falling_edge(clock);
    grant_valid <= '0';

    -- Let the chunker finish aligning the short packet, so the first
    -- credit exercises a partial frame rather than racing chunk
    -- availability.
    for i in 0 to 69 loop
      wait until falling_edge(clock);
    end loop;

    -- Credit barely above the flight margin: balance of 2, forcing a
    -- 2-byte not-last partial frame.
    credit <= to_unsigned(margin_c + 2, 16);
    credit_set <= '1';
    wait until falling_edge(clock);
    credit_set <= '0';

    for i in 0 to 9 loop
      wait until falling_edge(clock);
    end loop;

    -- Enough credit for the remainder of the chunk.
    credit <= to_unsigned(margin_c + 10, 16);
    credit_set <= '1';
    wait until falling_edge(clock);
    credit_set <= '0';

    for i in 0 to 9 loop
      wait until falling_edge(clock);
    end loop;

    byte_ready <= '0';
    wait until falling_edge(clock);

    -- Grant frame: opcode then 0x0123 little-endian.
    find(from_hex("f12301"), "grant frame (f1 23 01)");
    assert grant_sent_seen = 1
      report "expected exactly one grant_sent strobe"
      severity failure;
    -- Partial data frame: 2 bytes, not last.
    find(from_hex("01dead"), "partial data frame (01 de ad)");
    -- Remainder: 3 bytes, last.
    find(from_hex("42beef11"), "final data frame (42 be ef 11)");

    log_info("chunked_link master framer OK");
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
