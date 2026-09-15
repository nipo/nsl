library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity pixel_stream_decimator is
  generic(
    in_config_c: nsl_video.pixel_stream.config_t;
    out_config_c: nsl_video.pixel_stream.config_t;
    in_geometry_c: nsl_video.mode.geometry_t;
    out_geometry_c: nsl_video.mode.geometry_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    in_i: in nsl_video.pixel_stream.master_t;
    in_o: out nsl_video.pixel_stream.slave_t;

    out_o: out nsl_video.pixel_stream.master_t;
    out_i: in nsl_video.pixel_stream.slave_t;

    overflow_o: out std_ulogic
    );
end entity;

architecture beh of pixel_stream_decimator is

  -- What an accumulator takes on every pixel, and what it has to hold
  -- already for the next one to be kept.  Both are settled here rather
  -- than in the logic, which is what leaves one addition where there
  -- would otherwise be two.
  constant h_step_c : natural := out_geometry_c.width;
  constant h_threshold_c : natural := in_geometry_c.width - out_geometry_c.width;
  constant v_step_c : natural := out_geometry_c.height;
  constant v_threshold_c : natural := in_geometry_c.height - out_geometry_c.height;

  type regs_t is
  record
    h_acc: natural range 0 to in_geometry_c.width;
    v_acc: natural range 0 to in_geometry_c.height;
    -- Whether the line going by is one of the kept ones
    line_kept: std_ulogic;
    -- A frame opened and nothing has been let out of it yet
    frame_pending: std_ulogic;

    out_m: nsl_video.pixel_stream.master_t;
    overflow: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Leaving pixels out only makes a raster smaller, keeps "
      & "its pixels as they were, and takes one a beat",
      condition_c => in_config_c.pixel_count = 1
      and out_config_c.pixel_count = 1
      and in_config_c.component_count = out_config_c.component_count
      and in_config_c.component_bits = out_config_c.component_bits
      and in_geometry_c.width >= out_geometry_c.width
      and in_geometry_c.height >= out_geometry_c.height
      and out_geometry_c.width /= 0
      and out_geometry_c.height /= 0
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
      r.h_acc <= 0;
      r.v_acc <= 0;
      r.line_kept <= '0';
      r.frame_pending <= '0';
      r.out_m <= transfer_defaults(out_config_c);
      r.overflow <= '0';
    end if;
  end process;

  -- A raster off a wire cannot be asked to wait, so neither is this
  in_o <= accept(in_config_c, true);

  transition: process(r, in_i, out_i) is
    variable keep_line, keep_pixel: boolean;
  begin
    rin <= r;
    rin.overflow <= '0';

    -- A beat taken makes room for the next
    if is_taken(out_config_c, r.out_m, out_i) then
      rin.out_m <= transfer_defaults(out_config_c);
    end if;

    if is_valid(in_config_c, in_i) then
      -- A frame opens the vertical count again, and the first line of
      -- it is judged like any other
      if is_sof(in_config_c, in_i) then
        keep_line := 0 >= v_threshold_c;
        if keep_line then
          rin.v_acc <= 0 - v_threshold_c;
        else
          rin.v_acc <= 0 + v_step_c;
        end if;
        rin.frame_pending <= '1';
      else
        keep_line := r.line_kept = '1';
      end if;

      keep_pixel := keep_line and r.h_acc >= h_threshold_c;

      if keep_pixel then
        if is_valid(out_config_c, r.out_m)
          and not is_taken(out_config_c, r.out_m, out_i) then
          rin.overflow <= '1';
        else
          rin.out_m <= transfer(
            cfg => out_config_c,
            pixel => pixel(in_config_c, in_i),
            -- The last pixel of a line is always kept, so a line ends
            -- where it ended; the same goes for a frame
            last => is_last(in_config_c, in_i),
            sof => r.frame_pending = '1',
            eof => is_eof(in_config_c, in_i),
            error => is_error(in_config_c, in_i));

          rin.frame_pending <= '0';
        end if;
      end if;

      -- Only a line being kept moves the count along.  A line being
      -- dropped would run it far past anything it can hold, and what
      -- it held would be thrown away at the end of the line anyway.
      if keep_line then
        if keep_pixel then
          rin.h_acc <= r.h_acc - h_threshold_c;
        else
          rin.h_acc <= r.h_acc + h_step_c;
        end if;
      end if;

      -- A line closing settles whether the next one is kept, and opens
      -- the horizontal count again
      if is_last(in_config_c, in_i) then
        rin.h_acc <= 0;

        if is_eof(in_config_c, in_i) then
          -- The next line belongs to the next frame, which states
          -- itself
          rin.line_kept <= '0';
        elsif r.v_acc >= v_threshold_c then
          rin.line_kept <= '1';
          rin.v_acc <= r.v_acc - v_threshold_c;
        else
          rin.line_kept <= '0';
          rin.v_acc <= r.v_acc + v_step_c;
        end if;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= r.out_m;
    overflow_o <= r.overflow;
  end process;

end architecture;
