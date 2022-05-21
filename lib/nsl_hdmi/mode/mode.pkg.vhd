library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.arith.to_unsigned_auto;

package mode is

  type dimension_timings_t is
  record
    active, blank, off, width: natural;
    sync: std_ulogic;
  end record;

  type mode_t is
  record
    h, v : dimension_timings_t;
    fps: real;
  end record;

  function h_fp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function h_sync_m1(mode: mode_t; width : integer := 0) return unsigned;
  function h_bp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function h_act_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_fp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_sync_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_bp_m1(mode: mode_t; width : integer := 0) return unsigned;
  function v_act_m1(mode: mode_t; width : integer := 0) return unsigned;
  function pixel_clock(mode: mode_t) return real;
  
  function mode_build(h_active, h_blank, h_off, h_width,
                    v_active, v_blank, v_off, v_width : integer;
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

  -- VIC 1
  -- PxClk = 25.175
  constant mode_std_640x480p5994_c: mode_t := mode_build(640, 160, 16, 96, 480, 45, 10, 2, 59.94, '0', '0');
  -- VIC 2,3
  -- PxClk = 27
  constant mode_std_720x480p5994_c: mode_t := mode_build(720, 138, 16, 62, 480, 45, 9, 6, 59.94, '0', '0');

end package mode;

package body mode is

  function mode_build(h_active, h_blank, h_off, h_width,
                      v_active, v_blank, v_off, v_width : integer;
                      fps: real;
                      hpol, vpol: std_ulogic) return mode_t
  is
    variable ret : mode_t;
  begin
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

  function pixel_clock(mode: mode_t) return real
  is
  begin
    return mode.fps * real(mode.h.active + mode.h.blank) * real(mode.v.active + mode.v.blank);
  end function;

end package body;
