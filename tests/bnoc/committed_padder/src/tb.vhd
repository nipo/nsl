library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_bnoc.testing.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  constant min_size_c : positive := 8;
  constant padding_byte_c : byte := x"ff";

  signal in_s, out_s : nsl_bnoc.committed.committed_bus;

begin

  gen: process
  begin
    in_s.req.valid <= '0';
    wait for 100 ns;

    -- Test 1: Frame shorter than min_size (4 bytes < 8)
    -- Expected output: 4 data bytes + 4 padding bytes + commit
    log_info("Test 1: Sending 4 bytes (should be padded to 8)");
    committed_put(in_s.req, in_s.ack, clock_s,
                  from_hex("01020304"), true,
                  1, 3);

    wait for 100 ns;

    -- Test 2: Frame equal to min_size (8 bytes)
    -- Expected output: 8 data bytes + commit (no padding)
    log_info("Test 2: Sending 8 bytes (no padding needed)");
    committed_put(in_s.req, in_s.ack, clock_s,
                  from_hex("0102030405060708"), true,
                  1, 3);

    wait for 100 ns;

    -- Test 3: Frame longer than min_size (12 bytes > 8)
    -- Expected output: 12 data bytes + commit (no padding)
    log_info("Test 3: Sending 12 bytes (no padding needed)");
    committed_put(in_s.req, in_s.ack, clock_s,
                  from_hex("0102030405060708090a0b0c"), true,
                  1, 3);

    wait for 100 ns;

    -- Test 4: Very short frame (1 byte < 8)
    -- Expected output: 1 data byte + 7 padding bytes + commit
    log_info("Test 4: Sending 1 byte (should be padded to 8)");
    committed_put(in_s.req, in_s.ack, clock_s,
                  from_hex("aa"), true,
                  1, 3);

    wait for 100 ns;

    -- Test 5: Empty frame (0 bytes < 8)
    -- Expected output: 8 padding bytes + commit
    log_info("Test 5: Sending 0 bytes (should be padded to 8)");
    committed_put(in_s.req, in_s.ack, clock_s,
                  from_hex(""), true,
                  1, 3);

    wait for 100 ns;

    -- Test 6: Short frame with cancel status (3 bytes < 8)
    -- Expected output: 3 data bytes + 5 padding bytes + cancel
    log_info("Test 6: Sending 3 bytes with cancel status");
    committed_put(in_s.req, in_s.ack, clock_s,
                  from_hex("112233"), false,
                  1, 3);

    wait;
  end process;

  chk: process
  begin
    done_s(0) <= '0';
    out_s.ack.ready <= '0';
    wait for 100 ns;

    -- Check 1: 4 bytes padded to 8
    log_info("Checking test 1: expecting 4 data + 4 padding bytes");
    committed_check("padder test 1",
                    out_s.req, out_s.ack, clock_s,
                    from_hex("01020304ffffffff"), true, LOG_LEVEL_FATAL,
                    1, 2);

    -- Check 2: 8 bytes, no padding
    log_info("Checking test 2: expecting 8 data bytes, no padding");
    committed_check("padder test 2",
                    out_s.req, out_s.ack, clock_s,
                    from_hex("0102030405060708"), true, LOG_LEVEL_FATAL,
                    1, 2);

    -- Check 3: 12 bytes, no padding
    log_info("Checking test 3: expecting 12 data bytes, no padding");
    committed_check("padder test 3",
                    out_s.req, out_s.ack, clock_s,
                    from_hex("0102030405060708090a0b0c"), true, LOG_LEVEL_FATAL,
                    1, 2);

    -- Check 4: 1 byte padded to 8
    log_info("Checking test 4: expecting 1 data + 7 padding bytes");
    committed_check("padder test 4",
                    out_s.req, out_s.ack, clock_s,
                    from_hex("aaffffffffffffff"), true, LOG_LEVEL_FATAL,
                    1, 2);

    -- Check 5: 0 bytes padded to 8
    log_info("Checking test 5: expecting 8 padding bytes");
    committed_check("padder test 5",
                    out_s.req, out_s.ack, clock_s,
                    from_hex("ffffffffffffffff"), true, LOG_LEVEL_FATAL,
                    1, 2);

    -- Check 6: 3 bytes padded to 8 with cancel status
    log_info("Checking test 6: expecting 3 data + 5 padding bytes with cancel");
    committed_check("padder test 6",
                    out_s.req, out_s.ack, clock_s,
                    from_hex("112233ffffffffff"), false, LOG_LEVEL_FATAL,
                    1, 2);

    log_info("All padder tests passed");
    done_s(0) <= '1';
    wait;
  end process;

  dut: nsl_bnoc.committed.committed_padder
    generic map(
      min_size_c => min_size_c,
      padding_byte_c => padding_byte_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => in_s.req,
      in_o => in_s.ack,
      out_o => out_s.req,
      out_i => out_s.ack
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
