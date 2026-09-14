library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_amba, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_data.text.all;

-- A panel whose scan starts before the stream feeding it does.
--
-- A raster that owns its timing opens a frame, then stands at its
-- first pixel until one is handed over, and opens the next frame only
-- once it has finished this one.  A stream arriving off a link takes
-- seconds to say anything.  So the frame the raster opens is opened
-- while the unframer is still throwing beats away looking for the
-- start of one, and if that is forgotten the two wait on each other
-- and neither ever moves.
--
-- Which is exactly what a display shows as nothing at all.
entity tb is
end entity;

architecture arch of tb is

  constant geometry_c: geometry_t := geometry(16, 8);
  constant config_c: config_t := config(pixels => 1);

  -- Long enough that the raster is well into waiting by the time the
  -- stream says anything
  constant stream_delay_c: natural := 2000;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal stream_s: nsl_video.pixel_stream.bus_t;

  signal sof_s, sol_s, ready_s, valid_s, synced_s: std_ulogic;
  signal raster_sof_s: std_ulogic;
  signal pixel_s: pixel_t;

  signal taken_s: natural;
  signal frames_s: natural;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

  unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => config_c,
      raster_can_wait_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => stream_s.m,
      in_o => stream_s.s,

      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => ready_s,
      valid_o => valid_s,
      pixel_o => pixel_s,

      synced_o => synced_s
      );

  sof_s <= raster_sof_s;

  -- The stream, which says nothing for a while and then sends frames
  source: process is
  begin
    stream_s.m <= transfer_defaults(config_c);

    wait until reset_n_s = '1';

    for i in 0 to stream_delay_c-1
    loop
      wait until rising_edge(clock_s);
    end loop;

    loop
      for y in 0 to geometry_c.height-1
      loop
        for x in 0 to geometry_c.width-1
        loop
          stream_s.m <= transfer(
            config_c,
            pixel_t'(0 => to_unsigned(x, 16),
                     1 => to_unsigned(y, 16),
                     others => (others => '0')),
            sof => x = 0 and y = 0,
            last => x = geometry_c.width-1,
            eof => x = geometry_c.width-1 and y = geometry_c.height-1);

          loop
            wait until rising_edge(clock_s);
            exit when is_taken(config_c, stream_s.m, stream_s.s);
          end loop;
        end loop;
      end loop;
    end loop;
  end process;

  -- The panel scan, shaped like the one in a real display driver: it
  -- opens a frame, opens a line, then asks for pixels one at a time
  -- and waits for each.  It opens another frame only once this one is
  -- done.
  raster: process is
    variable x, y: natural;
  begin
    raster_sof_s <= '0';
    sol_s <= '0';
    ready_s <= '0';
    taken_s <= 0;
    frames_s <= 0;

    wait until reset_n_s = '1';

    -- Land on an edge, so that a pulse a cycle wide really does span
    -- one.  Driving it in the same simulation time as the edge that
    -- releases reset leaves no edge to sample it.
    wait until rising_edge(clock_s);

    loop
      -- Frame opens, for one cycle
      raster_sof_s <= '1';
      wait until rising_edge(clock_s);
      raster_sof_s <= '0';

      for line in 0 to geometry_c.height-1
      loop
        sol_s <= '1';
        wait until rising_edge(clock_s);
        sol_s <= '0';

        for column in 0 to geometry_c.width-1
        loop
          ready_s <= '1';
          loop
            wait until rising_edge(clock_s);
            exit when valid_s = '1';
          end loop;
          ready_s <= '0';

          taken_s <= taken_s + 1;
          wait until rising_edge(clock_s);
        end loop;
      end loop;

      frames_s <= frames_s + 1;
    end loop;
  end process;

  main: process is
    variable waited: natural := 0;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    -- Well past the point where the stream started talking
    while waited < stream_delay_c + 100 * geometry_c.width * geometry_c.height
    loop
      wait until rising_edge(clock_s);
      waited := waited + 1;
      exit when frames_s >= 2;
    end loop;

    report "DBG synced=" & std_ulogic'image(synced_s)
      & " frames=" & to_string(frames_s)
      & " taken=" & to_string(taken_s)
      & " stream_ready=" & boolean'image(is_ready(config_c, stream_s.s))
      & " stream_valid=" & boolean'image(is_valid(config_c, stream_s.m))
      & " unframer_valid=" & std_ulogic'image(valid_s)
      & " raster_ready=" & std_ulogic'image(ready_s)
      severity note;

    assert synced_s = '1'
      report "The unframer never found a frame in a stream that was sending them"
      severity failure;
    assert frames_s >= 2
      report "The panel got " & to_string(frames_s)
      & " whole frames out of a stream that started late, having taken "
      & to_string(taken_s) & " pixels"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
