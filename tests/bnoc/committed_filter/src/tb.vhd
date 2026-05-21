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

  -- Cancellable buffer holds 2 ** log2(max_size_c - 1) = 64 words. A committed
  -- frame occupies (data bytes + 1 last flit) words, so up to 63 data bytes
  -- fit; 64 data bytes or more overflow.
  constant max_size_c : positive := 64;

  signal in_s, out_s : nsl_bnoc.committed.committed_bus;

  -- Frames that fit and are committed: must come out unchanged.
  constant frame_a_c : byte_string(0 to 15) := (others => x"a1");
  constant frame_c_c : byte_string(0 to 15) := (others => x"c3");
  constant frame_f_c : byte_string(0 to 15) := (others => x"f6");
  constant frame_h_c : byte_string(0 to 15) := (others => x"18");
  -- Largest frame that still fits (63 data bytes).
  constant frame_max_c : byte_string(0 to 62) := (others => x"d4");

  -- Frames the filter must drop, producing no output at all:
  --  - oversized frame, overflow happens on a data flit
  constant frame_big_c : byte_string(0 to 199) := (others => x"b2");
  --  - oversized frame by exactly one flit, overflow happens on the last flit
  constant frame_over_c : byte_string(0 to 63) := (others => x"e5");
  --  - well-sized frame, but cancelled by the producer
  constant frame_cancel_c : byte_string(0 to 15) := (others => x"07");

begin

  gen: process
  begin
    in_s.req.valid <= '0';
    wait for 100 ns;
    -- Align stimulus to the falling edge so committed_put never starts
    -- driving exactly on a rising edge (which would race DUT sampling).
    wait until falling_edge(clock_s);

    log_info("Sending frame A (16 bytes, committed) - expected through");
    committed_put(in_s.req, in_s.ack, clock_s, frame_a_c, true, 1, 3);

    log_info("Sending oversized frame (200 bytes) - expected dropped");
    committed_put(in_s.req, in_s.ack, clock_s, frame_big_c, true, 1, 3);

    log_info("Sending frame C (16 bytes, committed) - expected through");
    committed_put(in_s.req, in_s.ack, clock_s, frame_c_c, true, 1, 3);

    log_info("Sending frame MAX (63 bytes, committed) - largest that fits");
    committed_put(in_s.req, in_s.ack, clock_s, frame_max_c, true, 1, 3);

    log_info("Sending overflow-by-one frame (64 bytes) - expected dropped");
    committed_put(in_s.req, in_s.ack, clock_s, frame_over_c, true, 1, 3);

    log_info("Sending frame F (16 bytes, committed) - expected through");
    committed_put(in_s.req, in_s.ack, clock_s, frame_f_c, true, 1, 3);

    log_info("Sending cancelled frame (16 bytes) - expected dropped");
    committed_put(in_s.req, in_s.ack, clock_s, frame_cancel_c, false, 1, 3);

    log_info("Sending frame H (16 bytes, committed) - expected through");
    committed_put(in_s.req, in_s.ack, clock_s, frame_h_c, true, 1, 3);

    wait;
  end process;

  -- The checker only expects the frames that must pass the filter. If a
  -- dropped frame leaked any flit, the next check would see wrong data and
  -- fail. If the filter deadlocked on an oversized frame (the bug this test
  -- guards against), the post-overflow checks would never complete.
  chk: process
  begin
    done_s(0) <= '0';
    out_s.ack.ready <= '0';
    wait for 100 ns;

    log_info("Checking frame A");
    committed_check("filter A", out_s.req, out_s.ack, clock_s,
                    frame_a_c, true, LOG_LEVEL_FATAL, 1, 2);

    log_info("Checking frame C (filter recovered after oversized frame)");
    committed_check("filter C", out_s.req, out_s.ack, clock_s,
                    frame_c_c, true, LOG_LEVEL_FATAL, 1, 2);

    log_info("Checking frame MAX (63 bytes)");
    committed_check("filter MAX", out_s.req, out_s.ack, clock_s,
                    frame_max_c, true, LOG_LEVEL_FATAL, 1, 2);

    log_info("Checking frame F (filter recovered after overflow-by-one)");
    committed_check("filter F", out_s.req, out_s.ack, clock_s,
                    frame_f_c, true, LOG_LEVEL_FATAL, 1, 2);

    log_info("Checking frame H (filter recovered after cancelled frame)");
    committed_check("filter H", out_s.req, out_s.ack, clock_s,
                    frame_h_c, true, LOG_LEVEL_FATAL, 1, 2);

    log_info("All committed_filter tests passed");
    done_s(0) <= '1';
    wait;
  end process;

  dut: nsl_bnoc.committed.committed_filter
    generic map(
      max_size_c => max_size_c
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
