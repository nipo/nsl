library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_clocking, nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Loopback unit test for the continuous_transport bit<->byte layer: the
-- serializer's outgoing bit stream is fed straight into the deserializer.
-- The deserializer must skip the alignment pad and preamble, lock on the
-- SOF, and recover exactly the payload bytes the serializer was given.
entity tb is
end entity;

architecture arch of tb is

  constant payload_c : byte_string := from_hex("00112233445566778899aabbccddeeff");
  constant pad_c     : integer := 3;

  signal clock         : std_ulogic := '0';
  signal reset_n_async : std_ulogic := '0';
  signal reset_n       : std_ulogic;

  signal shift, capture, update : std_ulogic := '0';
  signal bit_wire       : std_ulogic;

  signal ser_byte : byte;
  signal ser_take : std_ulogic;

  signal des_locked, des_byte_valid : std_ulogic;
  signal des_byte : byte;

  signal done   : std_ulogic := '0';
  signal tx_idx : natural := 0;
  signal rx_idx : natural := 0;

begin

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock,
      data_i => reset_n_async,
      data_o => reset_n
      );

  ser_byte <= payload_c(payload_c'left + tx_idx) when tx_idx < payload_c'length
              else x"00";

  ser: nsl_jtag.continuous_transport.continuous_transport_serializer
    generic map(
      preamble_count_c => 2
      )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      shift_i => shift,
      capture_i => capture,
      update_i => update,
      pad_i => pad_c,
      tdo_o => bit_wire,
      byte_i => ser_byte,
      byte_ready_o => ser_take
    );

  des: nsl_jtag.continuous_transport.continuous_transport_deserializer
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      shift_i => shift,
      capture_i => capture,
      tdi_i => bit_wire,
      locked_o => des_locked,
      byte_o => des_byte,
      byte_valid_o => des_byte_valid
      );

  -- Advance the payload source each time the serializer consumes a byte.
  tx_proc: process(clock, reset_n)
  begin
    if reset_n = '0' then
      tx_idx <= 0;
    elsif rising_edge(clock) then
      if ser_take = '1' and tx_idx < payload_c'length then
        tx_idx <= tx_idx + 1;
      end if;
    end if;
  end process;

  -- Check each delivered byte against the expected payload.
  rx_proc: process(clock, reset_n)
  begin
    if reset_n = '0' then
      rx_idx <= 0;
    elsif rising_edge(clock) then
      if des_byte_valid = '1' then
        if rx_idx < payload_c'length then
          assert_equal("loopback", "payload byte",
                       des_byte, payload_c(payload_c'left + rx_idx), failure);
        end if;
        rx_idx <= rx_idx + 1;
      end if;
    end if;
  end process;

  stim: process
  begin
    shift <= '0';
    capture <= '0';
    wait for 50 ns;
    wait until rising_edge(clock);
    wait until rising_edge(clock);
    wait until rising_edge(clock);
    wait until rising_edge(clock);

    -- Batch start
    capture <= '1';
    wait until rising_edge(clock);
    capture <= '0';

    -- Shift the whole batch plus margin: pad + preamble + SOF + payload.
    shift <= '1';
    for i in 0 to 255 loop
      wait until rising_edge(clock);
    end loop;
    shift <= '0';
    wait until rising_edge(clock);

    assert des_locked = '1'
      report "deserializer never locked on SOF" severity failure;
    assert rx_idx >= payload_c'length
      report "deserializer delivered fewer bytes than the payload" severity failure;
    log_info("continuous_transport loopback OK");

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
