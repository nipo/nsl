library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_bnoc;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.pipe.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  -- Frame in -> chunker -> pipe -> unchunker -> frame out
  signal frame_in_s, frame_out_s : nsl_bnoc.framed.framed_bus;
  signal pipe_s : nsl_bnoc.pipe.pipe_bus_t;
  signal unchunker_reset_n_s : std_ulogic;

  -- Small chunk window (16 bytes) so the frames below span one,
  -- exactly one full, and several chunks.
  constant max_txn_length_l2_c : natural := 4;

  -- One frame per data set, exercising the chunk boundaries.
  constant frame0_c : byte_string := from_hex("5a");                          -- 1 byte
  constant frame1_c : byte_string := to_byte_string("Hi");                    -- 2 bytes
  constant frame2_c : byte_string := to_byte_string("0123456789abcdef");      -- 16 bytes, one full chunk
  constant frame3_c : byte_string := to_byte_string("0123456789abcdefg");     -- 17 bytes, two chunks
  constant frame4_c : byte_string := to_byte_string("The quick brown fox jumps over the lazy dog."); -- 44 bytes, three chunks

begin

  gen: process
  begin
    frame_in_s.req.valid <= '0';

    wait for 30 ns;
    wait until falling_edge(clock_s);

    -- Steady stream first.
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame0_c);
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame1_c);
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame2_c);
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame3_c);
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame4_c);

    -- Then throttle the input side (1 flit every 3 cycles) to exercise
    -- chunker backpressure on the framed input.
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame4_c, 1, 3);
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame3_c, 1, 3);
    framed_put(frame_in_s.req, frame_in_s.ack, clock_s, frame0_c, 1, 3);

    wait;
  end process;

  chunker: nsl_bnoc.framed.framed_chunker
    generic map(
      max_txn_length_l2_c => max_txn_length_l2_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => frame_in_s.req,
      in_o => frame_in_s.ack,

      out_o => pipe_s.req,
      out_i => pipe_s.ack
      );

  unchunker: nsl_bnoc.framed.framed_unchunker
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => pipe_s.req,
      in_o => pipe_s.ack,

      reset_n_o => unchunker_reset_n_s,

      out_o => frame_out_s.req,
      out_i => frame_out_s.ack
      );

  chk: process
  begin
    done_s(0) <= '0';
    frame_out_s.ack.ready <= '0';

    wait for 10 ns;

    framed_check("frame0", frame_out_s.req, frame_out_s.ack, clock_s, frame0_c, LOG_LEVEL_ERROR);
    framed_check("frame1", frame_out_s.req, frame_out_s.ack, clock_s, frame1_c, LOG_LEVEL_ERROR);
    framed_check("frame2", frame_out_s.req, frame_out_s.ack, clock_s, frame2_c, LOG_LEVEL_ERROR);
    framed_check("frame3", frame_out_s.req, frame_out_s.ack, clock_s, frame3_c, LOG_LEVEL_ERROR);
    framed_check("frame4", frame_out_s.req, frame_out_s.ack, clock_s, frame4_c, LOG_LEVEL_ERROR);

    framed_check("frame4 throttled-in", frame_out_s.req, frame_out_s.ack, clock_s, frame4_c, LOG_LEVEL_ERROR);
    framed_check("frame3 throttled-in", frame_out_s.req, frame_out_s.ack, clock_s, frame3_c, LOG_LEVEL_ERROR);

    -- Throttle the framed output side too (1 flit every 3 cycles).
    framed_check("frame0 throttled-out", frame_out_s.req, frame_out_s.ack, clock_s, frame0_c, LOG_LEVEL_ERROR, 1, 3);

    done_s(0) <= '1';
    wait;
  end process;

  -- The chunker never emits reset markers, so the unchunker's reset
  -- output must stay deasserted (high) the whole time.
  reset_check: process
  begin
    done_s(1) <= '0';
    wait until reset_n_s = '1';

    while done_s(0) = '0' loop
      wait until rising_edge(clock_s);
      assert unchunker_reset_n_s = '1'
        report "unchunker asserted reset_n_o without a reset marker"
        severity error;
    end loop;

    done_s(1) <= '1';
    wait;
  end process;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 1 ns,
      reset_duration => (others => 7 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
