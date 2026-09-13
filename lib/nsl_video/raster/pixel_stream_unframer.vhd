library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity pixel_stream_unframer is
  generic(
    config_c: nsl_video.pixel_stream.config_t;
    raster_can_wait_c: boolean := false
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    in_i: in nsl_video.pixel_stream.master_t;
    in_o: out nsl_video.pixel_stream.slave_t;

    sof_i: in std_ulogic;
    sol_i: in std_ulogic;
    ready_i: in std_ulogic;
    valid_o: out std_ulogic;
    pixel_o: out nsl_video.pixel_stream.pixel_t;

    synced_o: out std_ulogic
    );
end entity;

architecture beh of pixel_stream_unframer is

  type state_t is (
    ST_RESET,
    -- Stream is somewhere unknown in a frame, take beats and throw
    -- them away until one opens a frame.
    ST_DRAIN,
    -- Stream offers the first pixel of a frame, hold it until the
    -- raster asks for one.
    ST_ARMED,
    ST_SYNCED
    );

  type regs_t is
  record
    state: state_t;
    -- Last pixel taken closed a line, and closed a frame.
    line_closed, frame_closed: boolean;
    -- A raster opened a frame while the stream was still being
    -- drained.  Only a raster that can wait is still standing at the
    -- start of that frame once draining ends, so only then is it worth
    -- remembering.
    raster_opened: boolean;
  end record;

  signal r, rin: regs_t;

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A raster takes one pixel at a time, stream must hold one pixel per beat",
      condition_c => config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  ready_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Unframer takes beats one raster pixel at a time, stream must carry ready",
      condition_c => nsl_video.pixel_stream.has_ready(config_c)
      )
    port map(
      unused_i => '0'
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.raster_opened <= false;
    end if;
  end process;

  transition: process(r, in_i, sof_i, sol_i, ready_i) is
    variable valid, taken: boolean;
  begin
    rin <= r;

    valid := is_valid(config_c, in_i);

    -- A raster that can wait cannot leave the start of a frame it
    -- opened until it is given a pixel, so a frame it opened while the
    -- stream was being drained is the frame it is still standing at.
    -- Without keeping that, the two wait on each other for good: the
    -- raster holds at its first pixel for a stream that will not
    -- speak, and the stream holds for a frame the raster has already
    -- opened and will not open again until it has finished this one.
    -- Which is what happens whenever a stream starts late -- a link
    -- taking seconds to come up, say.
    if raster_can_wait_c and sof_i = '1' then
      rin.raster_opened <= true;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_DRAIN;

      when ST_DRAIN =>
        if valid and is_sof(config_c, in_i) then
          rin.state <= ST_ARMED;
        end if;

      when ST_ARMED =>
        -- A raster that can wait and is asking for a pixel is a raster
        -- that will not move until it gets one, and it opens its next
        -- frame only once it has finished this one.  Holding out for a
        -- frame boundary it can never reach leaves it dark for good,
        -- which is worse than one frame arriving out of step: the next
        -- boundary puts that right.
        if sof_i = '1' or r.raster_opened
          or (raster_can_wait_c and ready_i = '1') then
          rin.state <= ST_SYNCED;
          rin.line_closed <= true;
          rin.frame_closed <= true;
          rin.raster_opened <= false;
        end if;

      when ST_SYNCED =>
        taken := valid and ready_i = '1';

        if taken then
          rin.line_closed <= is_last(config_c, in_i);
          rin.frame_closed <= is_last(config_c, in_i) and is_eof(config_c, in_i);
        end if;

        -- A raster that cannot wait loses the pixel it asked for and
        -- the stream did not hold, and every later pixel of the frame
        -- shifts by one.  That is a loss of sync, not a one-pixel
        -- glitch.  A raster that can wait just waits.
        if not raster_can_wait_c and ready_i = '1' and not valid then
          rin.state <= ST_DRAIN;
        end if;

        -- The raster states where a line and a frame start. What the
        -- stream last closed has to agree.
        if sol_i = '1' and not r.line_closed then
          rin.state <= ST_DRAIN;
        end if;

        if sof_i = '1' and not r.frame_closed then
          rin.state <= ST_DRAIN;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, ready_i) is
  begin
    in_o <= accept(config_c, ready => false);
    valid_o <= '0';
    synced_o <= '0';

    case r.state is
      when ST_RESET | ST_ARMED =>
        null;

      when ST_DRAIN =>
        -- Take everything but the beat opening a frame: that one has
        -- to still be there when the raster asks for its first pixel.
        in_o <= accept(config_c,
                       ready => not (is_valid(config_c, in_i)
                                     and is_sof(config_c, in_i)));

      when ST_SYNCED =>
        synced_o <= '1';
        in_o <= accept(config_c, ready => ready_i = '1');
        if is_valid(config_c, in_i) then
          valid_o <= '1';
        end if;
    end case;

    pixel_o <= pixel(config_c, in_i);
  end process;

end architecture;
