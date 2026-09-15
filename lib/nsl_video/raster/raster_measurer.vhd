library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;
use nsl_video.mode.all;

entity raster_measurer is
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    de_i: in std_ulogic;
    hsync_i: in std_ulogic;
    vsync_i: in std_ulogic;

    timings_o: out nsl_video.mode.timings_t;
    valid_o: out std_ulogic
    );
end entity;

architecture beh of raster_measurer is

  constant count_max_c: count_t := (others => '1');

  -- What one axis is being counted into.  Horizontal counts symbols
  -- and vertical counts lines, so the two run on the same shape.
  type axis_regs_t is
  record
    -- Level the sync sits at while the raster is active, which is by
    -- definition the level it is not asserted at.
    idle: std_ulogic;
    idle_known: boolean;

    -- Counting the period, the active part of it, the sync pulse, and
    -- the gap between the end of active and the start of the sync.
    total, active, width, off: count_t;
    -- Whether the gap is still being counted, which it is from the
    -- end of active until the sync starts.
    in_off: boolean;
    -- Sync as it was last looked at, so its start can be told from
    -- the rest of the pulse.
    was_asserted: boolean;

  end record;

  type regs_t is
  record
    h, v: axis_regs_t;

    -- Last line that showed pixels, measured.  A blanking line
    -- measures a line that is not the one being looked for.
    line: axis_timings_t;
    line_seen: boolean;
    -- Whether the line being measured has shown pixels.
    line_active: boolean;

    -- What is on the outputs, and whether the frame before it
    -- measured the same.  Both axes change together, at a frame
    -- boundary, so what is offered is always one frame's worth and
    -- valid always speaks about it.
    offered: timings_t;
    stable: boolean;
  end record;

  signal r, rin: regs_t;

  -- Counters stop at the top rather than wrapping, so a period that
  -- never ends measures something that cannot match anything.
  function bumped(v: count_t) return count_t
  is
  begin
    if v = count_max_c then
      return v;
    end if;
    return v + 1;
  end function;

  -- What a period measured, once it ended.  Blanking is what the
  -- period holds beyond its active part.
  function measured(axis: axis_regs_t; total: count_t) return axis_timings_t
  is
  begin
    return axis_timings_t'(
      active => axis.active,
      blank => total - axis.active,
      off => axis.off,
      width => axis.width,
      sync => not axis.idle);
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.h.idle_known <= false;
      r.v.idle_known <= false;
      r.h.total <= (others => '0');
      r.v.total <= (others => '0');
      r.h.active <= (others => '0');
      r.v.active <= (others => '0');
      r.h.width <= (others => '0');
      r.v.width <= (others => '0');
      r.h.off <= (others => '0');
      r.v.off <= (others => '0');
      r.h.in_off <= false;
      r.v.in_off <= false;
      r.h.was_asserted <= false;
      r.v.was_asserted <= false;
      r.line_seen <= false;
      r.line_active <= false;
      r.stable <= false;
    end if;
  end process;

  transition: process(r, de_i, hsync_i, vsync_i) is
    variable h_asserted, v_asserted: boolean;
    variable h_starts, v_starts, line_ends: boolean;
    variable v_total, v_active, v_off, v_width: count_t;
    variable v_in_off: boolean;
    variable frame: axis_timings_t;
  begin
    rin <= r;

    -- A sync is asserted whenever it sits away from the level it
    -- holds while the raster is active.
    h_asserted := r.h.idle_known and hsync_i /= r.h.idle;
    v_asserted := r.v.idle_known and vsync_i /= r.v.idle;

    -- Active video says what the idle level is, since no sync is ever
    -- asserted while it runs.
    if de_i = '1' then
      rin.h.idle <= hsync_i;
      rin.h.idle_known <= true;
      rin.v.idle <= vsync_i;
      rin.v.idle_known <= true;
    end if;

    -- A line starts where the horizontal sync does, and the vertical
    -- axis counts lines, so it moves on the same edge.  The vertical
    -- sync is only looked at there, so that is where its own start is
    -- told apart from the rest of its pulse.
    h_starts := h_asserted and not r.h.was_asserted;
    line_ends := h_starts;
    v_starts := line_ends and v_asserted and not r.v.was_asserted;

    rin.h.was_asserted <= h_asserted;
    if line_ends then
      rin.v.was_asserted <= v_asserted;
    end if;

    -- Horizontal, counted in symbols

    rin.h.total <= bumped(r.h.total);

    if de_i = '1' then
      rin.h.active <= bumped(r.h.active);
      rin.h.off <= (others => '0');
      rin.h.in_off <= true;
      rin.line_active <= true;
    elsif r.h.in_off and not h_asserted then
      rin.h.off <= bumped(r.h.off);
    end if;

    if h_asserted then
      rin.h.width <= bumped(r.h.width);
      rin.h.in_off <= false;
    end if;

    if h_starts then
      if r.line_active then
        rin.line <= measured(r.h, r.h.total);
        rin.line_seen <= true;
      end if;

      rin.h.total <= to_unsigned(1, count_t'length);
      rin.h.active <= (others => '0');
      rin.h.width <= to_unsigned(1, count_t'length);
      rin.h.off <= (others => '0');
    end if;

    -- Vertical, counted in lines.
    --
    -- One line goes by per look, so what is counted at a line
    -- boundary is the line that just ended, and the sync state that
    -- line held is the one seen at the boundary before it.  A frame
    -- whose sync starts right behind its last active line would
    -- otherwise lose that line, and a front porch of one line would
    -- be swallowed by the sync edge closing it.

    if line_ends then
      v_total := bumped(r.v.total);
      v_active := r.v.active;
      v_off := r.v.off;
      v_width := r.v.width;
      v_in_off := r.v.in_off;

      if r.line_active then
        v_active := bumped(r.v.active);
        v_off := (others => '0');
        v_in_off := true;
      elsif r.v.in_off and not r.v.was_asserted then
        v_off := bumped(r.v.off);
      end if;

      if r.v.was_asserted then
        v_width := bumped(r.v.width);
        v_in_off := false;
      end if;

      rin.v.total <= v_total;
      rin.v.active <= v_active;
      rin.v.off <= v_off;
      rin.v.width <= v_width;
      rin.v.in_off <= v_in_off;
      rin.line_active <= false;

      if v_starts then
        frame := axis_timings_t'(
          active => v_active,
          blank => v_total - v_active,
          off => v_off,
          width => v_width,
          sync => not r.v.idle);

        rin.offered <= timings_t'(h => r.line, v => frame);

        -- What is offered is worth taking once the frame before it
        -- measured the same, which is what tells a settled link from
        -- one still coming up, or from noise.
        rin.stable <= r.line_seen
                      and r.line = r.offered.h
                      and frame = r.offered.v
                      and r.h.idle_known and r.v.idle_known;

        rin.v.total <= (others => '0');
        rin.v.active <= (others => '0');
        rin.v.width <= (others => '0');
        rin.v.off <= (others => '0');
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    timings_o <= r.offered;

    if r.stable then
      valid_o <= '1';
    else
      valid_o <= '0';
    end if;
  end process;

end architecture;
