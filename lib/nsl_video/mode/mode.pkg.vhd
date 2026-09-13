library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math;
use nsl_math.arith.to_unsigned_auto;

-- Video mode timings, and the clocks they call for.
--
-- A mode states what a frame looks like: active pixels and lines,
-- the blanking around them, and the sync pulses inside that
-- blanking.  Two families state the remaining number differently:
--
-- - broadcast modes (CEA/HDMI) state a frame rate, and the pixel
--   clock follows from the frame geometry,
--
-- - computer modes (VESA/DMT) state a pixel clock, and the frame
--   rate follows.  1024x768 at "60 Hz" runs at 65 MHz, which is
--   60.004 frames per second, not 60.
--
-- Both constructors fill the same record, so a mode always knows its
-- pixel clock exactly.  That matters for clock generation: the PLL
-- solver takes an integer rate and holds it exactly, so a rate
-- rounded off a frame rate would either fail to map or produce a
-- clock a hair away from the standard one.
--
-- DVI carries ten bits per pixel per channel.  Sending them on both
-- clock edges makes the serial clock five times the pixel clock,
-- which serial_clock_hz() states.
--
-- A geometry is the part of a mode a pixel stream cares about: how
-- many pixels a line holds and how many lines a frame holds.
-- Blanking and clocks belong to the wire, not to the pixels, so a
-- frame generator or a panel driver takes a geometry and never sees
-- a mode.
package mode is
  type dimension_timings_t is
  record
    active, blank, off, width: natural;
    sync: std_ulogic;
  end record;

  type mode_t is
  record
    h, v : dimension_timings_t;
    -- Frame rate, nominal: the rate the mode is known by, which for
    -- a computer mode is not the rate it runs at.
    fps: real;
    -- Pixel clock, exact.
    pixel_hz: natural;
  end record;

  type geometry_t is
  record
    width, height: natural;
  end record;

  -- Counts a measured timing can hold.  4K needs 4400 symbols a line
  -- and 2250 lines a frame, so this leaves room.
  constant max_count_width_c: natural := 16;
  subtype count_t is unsigned(max_count_width_c-1 downto 0);

  -- The same numbers dimension_timings_t states, in a shape a signal
  -- can carry: a receiver measures these off the wire rather than
  -- being told them.  Clocks are not in here -- nothing about the
  -- syncs says what rate they arrive at.
  type axis_timings_t is
  record
    active, blank, off, width: count_t;
    sync: std_ulogic;
  end record;

  type timings_t is
  record
    h, v: axis_timings_t;
  end record;

  -- Timings of a mode, so a measurement can be held against one.
  function timings(mode: mode_t) return timings_t;
  -- Total a line and a frame hold, blanking included.
  function h_total(timings: timings_t) return count_t;
  function v_total(timings: timings_t) return count_t;

  function geometry(width, height: natural) return geometry_t;
  -- Active area of a mode.
  function geometry(mode: mode_t) return geometry_t;
  -- Pixels a frame holds.
  function pixel_count(geo: geometry_t) return natural;
  -- Bits an x or a y coordinate of this geometry needs.
  function x_width(geo: geometry_t) return natural;
  function y_width(geo: geometry_t) return natural;

  function h_fp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function h_sync_m1(mode: mode_t; width : integer := 0) return unsigned;
  function h_bp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function h_act_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_fp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_sync_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_bp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_act_m1(mode: mode_t; width : integer := 0) return unsigned;
  -- Pixel clock, as a rate in Hz and as a real.
  function pixel_clock_hz(mode: mode_t) return natural;
  function pixel_clock(mode: mode_t) return real;
  -- Serial clock of a DVI link, five times the pixel clock.
  function serial_clock_hz(mode: mode_t) return natural;
  -- Frame rate the mode actually runs at, which for a computer mode
  -- is not the rate it is known by.
  function refresh_rate(mode: mode_t) return real;
  -- Total frame geometry, blanking included.
  function h_total(mode: mode_t) return natural;
  function v_total(mode: mode_t) return natural;

  
  -- A mode stating its frame rate, the pixel clock following.
  function mode_build(h_active, h_blank, h_off, h_width,
                    v_active, v_blank, v_off, v_width : integer;
                    fps: real;
                    hpol, vpol : std_ulogic) return mode_t;

  -- A mode stating its pixel clock, the frame rate following.  fps
  -- is what the mode is known by, and is not used in any
  -- calculation.
  function mode_build_clocked(h_active, h_blank, h_off, h_width,
                    v_active, v_blank, v_off, v_width : integer;
                    pixel_hz: natural;
                    fps: real;
                    hpol, vpol : std_ulogic) return mode_t;

  -- VIC 31,75
  -- PxClk = 148.5
  constant mode_std_1920x1080p50_c: mode_t := mode_build(1920, 720, 528, 44, 1080, 45, 4, 5, 50.0, '1', '1');
  -- VIC 19,68
  -- PxClk = 74.25
  constant mode_std_1280x720p50_c: mode_t := mode_build(1280, 700, 440, 40, 720, 30, 5, 5, 50.0, '1', '1');
  -- VIC 17,18
  -- PxClk = 27
  constant mode_std_720x576p50_c: mode_t := mode_build(720, 144, 12, 64, 576, 49, 5, 5, 50.0, '0', '0');

  -- VIC 16,76
  -- PxClk = 148.5
  constant mode_std_1920x1080p60_c: mode_t := mode_build(1920, 280, 88, 44, 1080, 45, 4, 5, 60.0, '1', '1');
  -- VIC 4,69
  -- PxClk = 74.25
  constant mode_std_1280x720p60_c: mode_t := mode_build(1280, 370, 110, 40, 720, 30, 5, 5, 60.0, '1', '1');

  -- VIC 1.  Same, and the standard clock is not the geometry's
  -- either.
  constant mode_std_640x480p5994_c: mode_t := mode_build_clocked(640, 160, 16, 96, 480, 45, 10, 2, 25_175_000, 59.94, '0', '0');
  -- VIC 2,3.  59.94 is 60000/1001, which the literal below only
  -- approximates, hence the stated clock.
  constant mode_std_720x480p5994_c: mode_t := mode_build_clocked(720, 138, 16, 62, 480, 45, 9, 6, 27_000_000, 59.94, '0', '0');


  -- VESA/DMT computer modes, stated by their pixel clock.

  -- DMT 4, VGA
  constant mode_std_640x480p60_c: mode_t := mode_build_clocked(640, 160, 16, 96, 480, 45, 10, 2, 25_175_000, 60.0, '0', '0');
  -- DMT 9, SVGA
  constant mode_std_800x600p60_c: mode_t := mode_build_clocked(800, 256, 40, 128, 600, 28, 1, 4, 40_000_000, 60.0, '1', '1');
  -- DMT 16, XGA
  constant mode_std_1024x768p60_c: mode_t := mode_build_clocked(1024, 320, 24, 136, 768, 38, 3, 6, 65_000_000, 60.0, '0', '0');
  -- DMT 35, SXGA
  constant mode_std_1280x1024p60_c: mode_t := mode_build_clocked(1280, 408, 48, 112, 1024, 42, 1, 3, 108_000_000, 60.0, '1', '1');

end package mode;

package body mode is

  function mode_build(h_active, h_blank, h_off, h_width,
                      v_active, v_blank, v_off, v_width : integer;
                      fps: real;
                      hpol, vpol: std_ulogic) return mode_t
  is
    variable ret : mode_t;
  begin
    ret.pixel_hz := natural(round(fps
                                  * real(h_active + h_blank)
                                  * real(v_active + v_blank)));
    ret.h.active := h_active;
    ret.h.blank := h_blank;
    ret.h.off := h_off;
    ret.h.width := h_width;
    ret.h.sync := hpol;
    ret.v.active := v_active;
    ret.v.blank := v_blank;
    ret.v.off := v_off;
    ret.v.width := v_width;
    ret.v.sync := vpol;
    ret.fps := fps;

    return ret;
  end function;

  function mode_build_clocked(h_active, h_blank, h_off, h_width,
                              v_active, v_blank, v_off, v_width : integer;
                              pixel_hz: natural;
                              fps: real;
                              hpol, vpol: std_ulogic) return mode_t
  is
    variable ret : mode_t;
  begin
    ret := mode_build(h_active, h_blank, h_off, h_width,
                      v_active, v_blank, v_off, v_width,
                      fps, hpol, vpol);
    ret.pixel_hz := pixel_hz;

    return ret;
  end function;

  function timings(mode: mode_t) return timings_t
  is
    function axis(dim: dimension_timings_t) return axis_timings_t
    is
    begin
      return axis_timings_t'(
        active => to_unsigned(dim.active, max_count_width_c),
        blank => to_unsigned(dim.blank, max_count_width_c),
        off => to_unsigned(dim.off, max_count_width_c),
        width => to_unsigned(dim.width, max_count_width_c),
        sync => dim.sync);
    end function;
  begin
    return timings_t'(h => axis(mode.h), v => axis(mode.v));
  end function;

  function h_total(timings: timings_t) return count_t
  is
  begin
    return timings.h.active + timings.h.blank;
  end function;

  function v_total(timings: timings_t) return count_t
  is
  begin
    return timings.v.active + timings.v.blank;
  end function;

  function geometry(width, height: natural) return geometry_t
  is
  begin
    return geometry_t'(width => width, height => height);
  end function;

  function geometry(mode: mode_t) return geometry_t
  is
  begin
    return geometry(mode.h.active, mode.v.active);
  end function;

  function pixel_count(geo: geometry_t) return natural
  is
  begin
    return geo.width * geo.height;
  end function;

  function x_width(geo: geometry_t) return natural
  is
  begin
    return nsl_math.arith.log2(geo.width);
  end function;

  function y_width(geo: geometry_t) return natural
  is
  begin
    return nsl_math.arith.log2(geo.height);
  end function;

  function h_fp_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.h.off - 1);
    else
      return to_unsigned(mode.h.off - 1, width);
    end if;
  end function;

  function h_sync_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.h.width - 1);
    else
      return to_unsigned(mode.h.width - 1, width);
    end if;
  end function;

  function h_bp_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.h.blank - mode.h.off - mode.h.width - 1);
    else
      return to_unsigned(mode.h.blank - mode.h.off - mode.h.width - 1, width);
    end if;
  end function;

  function h_act_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.h.active - 1);
    else
      return to_unsigned(mode.h.active - 1, width);
    end if;
  end function;

  function v_fp_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.v.off - 1);
    else
      return to_unsigned(mode.v.off - 1, width);
    end if;
  end function;

  function v_sync_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.v.width - 1);
    else
      return to_unsigned(mode.v.width - 1, width);
    end if;
  end function;

  function v_bp_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.v.blank - mode.v.off - mode.v.width - 1);
    else
      return to_unsigned(mode.v.blank - mode.v.off - mode.v.width - 1, width);
    end if;
  end function;

  function v_act_m1(mode: mode_t; width : integer := 0) return unsigned
  is
  begin
    if width = 0 then
      return to_unsigned_auto(mode.v.active - 1);
    else
      return to_unsigned(mode.v.active - 1, width);
    end if;
  end function;

  function h_total(mode: mode_t) return natural
  is
  begin
    return mode.h.active + mode.h.blank;
  end function;

  function v_total(mode: mode_t) return natural
  is
  begin
    return mode.v.active + mode.v.blank;
  end function;

  function pixel_clock_hz(mode: mode_t) return natural
  is
  begin
    return mode.pixel_hz;
  end function;

  function pixel_clock(mode: mode_t) return real
  is
  begin
    return real(mode.pixel_hz);
  end function;

  function serial_clock_hz(mode: mode_t) return natural
  is
  begin
    return mode.pixel_hz * 5;
  end function;

  function refresh_rate(mode: mode_t) return real
  is
  begin
    return real(mode.pixel_hz) / real(h_total(mode)) / real(v_total(mode));
  end function;

end package body;
