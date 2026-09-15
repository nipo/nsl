library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;

entity pixel_stream_capturer is
  generic(
    config_c: nsl_video.pixel_stream.config_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    de_i: in std_ulogic;
    vsync_i: in std_ulogic;
    pixel_i: in nsl_video.pixel_stream.pixel_t;

    timings_i: in nsl_video.mode.timings_t;
    timings_valid_i: in std_ulogic;

    out_o: out nsl_video.pixel_stream.master_t;
    out_i: in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of pixel_stream_capturer is

  type state_t is (
    ST_RESET,
    -- Nothing is known about the frame being sent, so nothing goes
    -- out.
    ST_UNLOCKED,
    -- Waiting for the first pixel of a frame, which is what a stream
    -- opens on.
    ST_WAIT_SOF,
    ST_STREAMING
    );

  type regs_t is
  record
    state: state_t;

    -- Pixel taken last cycle, held until it is known whether another
    -- one follows it in the same line.
    held: pixel_t;
    held_valid: boolean;
    held_sof: boolean;

    -- Where in the frame the held pixel sits, and how long the frame
    -- was said to be when it opened.
    column, line: count_t;
    height, width: count_t;

    vsync_was_asserted: boolean;
    expect_sof: boolean;
  end record;

  signal r, rin: regs_t;

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A raster arrives one pixel at a time",
      condition_c => config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  -- A raster coming off a wire cannot be asked to wait, so neither can
  -- the stream it turns into.  Whatever takes it has to absorb it.
  no_ready_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A captured raster cannot be held back, stream must carry no ready",
      condition_c => not nsl_video.pixel_stream.has_ready(config_c)
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
      r.held_valid <= false;
      r.vsync_was_asserted <= false;
      r.expect_sof <= false;
    end if;
  end process;

  transition: process(r, de_i, vsync_i, pixel_i, timings_i, timings_valid_i) is
    variable v_asserted, frame_starts: boolean;
    variable ends_line: boolean;
  begin
    rin <= r;

    -- Polarity is not guessed here: the measurement states which way
    -- up the sync is.
    v_asserted := vsync_i = timings_i.v.sync;
    frame_starts := v_asserted and not r.vsync_was_asserted;
    rin.vsync_was_asserted <= v_asserted;

    -- The pixel held from last cycle is the last of its line when no
    -- pixel follows it.
    ends_line := r.held_valid and de_i = '0';

    case r.state is
      when ST_RESET =>
        rin.state <= ST_UNLOCKED;

      when ST_UNLOCKED =>
        -- Nothing goes out until the link settled, so frames measured
        -- while it was still coming up are not passed on.
        if timings_valid_i = '1' then
          rin.state <= ST_WAIT_SOF;
        end if;

      when ST_WAIT_SOF | ST_STREAMING =>
        if timings_valid_i = '0' then
          rin.state <= ST_UNLOCKED;
          rin.held_valid <= false;
          rin.expect_sof <= false;
        end if;
    end case;

    if ends_line then
      rin.line <= r.line + 1;
    end if;

    if frame_starts then
      -- Frame length is taken as the frame opens, so it holds for the
      -- whole of it however the measurement moves meanwhile.
      rin.height <= timings_i.v.active;
      rin.width <= timings_i.h.active;
      rin.line <= (others => '0');
      rin.expect_sof <= true;
    end if;

    -- Taking the pixel currently on the raster, and letting go of the
    -- one held before it.

    if r.state = ST_UNLOCKED then
      rin.held_valid <= false;
    elsif de_i = '1' then
      rin.held <= pixel_i;
      rin.held_valid <= true;
      rin.held_sof <= r.expect_sof;
      rin.expect_sof <= false;

      if r.held_valid then
        rin.column <= r.column + 1;
      else
        -- First pixel of a line
        rin.column <= (others => '0');
      end if;

      if r.expect_sof then
        rin.state <= ST_STREAMING;
      end if;
    else
      rin.held_valid <= false;
    end if;

  end process;

  mealy: process(r, de_i) is
    variable pixels: pixel_vector(0 to config_c.pixel_count-1);
    variable last, eof, error: boolean;
  begin
    pixels(0) := r.held;

    -- The held pixel closes its line when nothing follows it, and
    -- closes the frame when its line was the last of them.
    last := r.held_valid and de_i = '0';
    eof := last and r.line + 1 = r.height;
    error := last and (r.column + 1 /= r.width);

    out_o <= transfer(cfg => config_c,
                      pixels => pixels,
                      valid => r.held_valid and r.state = ST_STREAMING,
                      sof => r.held_sof,
                      last => last,
                      eof => eof,
                      error => error);
  end process;

end architecture;
