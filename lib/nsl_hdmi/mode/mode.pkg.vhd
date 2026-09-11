library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi;

-- Video mode timings, as nsl_dvi.mode states them.
--
-- DVI predates HDMI and the timings are the same, so the modes live
-- there and this package is the name HDMI users know them by.  New
-- code can use either.
package mode is

  subtype dimension_timings_t is nsl_dvi.mode.dimension_timings_t;
  subtype mode_t is nsl_dvi.mode.mode_t;

  alias h_fp_m1 is nsl_dvi.mode.h_fp_m1[mode_t, integer return unsigned];
  alias h_sync_m1 is nsl_dvi.mode.h_sync_m1[mode_t, integer return unsigned];
  alias h_bp_m1 is nsl_dvi.mode.h_bp_m1[mode_t, integer return unsigned];
  alias h_act_m1 is nsl_dvi.mode.h_act_m1[mode_t, integer return unsigned];
  alias v_fp_m1 is nsl_dvi.mode.v_fp_m1[mode_t, integer return unsigned];
  alias v_sync_m1 is nsl_dvi.mode.v_sync_m1[mode_t, integer return unsigned];
  alias v_bp_m1 is nsl_dvi.mode.v_bp_m1[mode_t, integer return unsigned];
  alias v_act_m1 is nsl_dvi.mode.v_act_m1[mode_t, integer return unsigned];
  alias pixel_clock is nsl_dvi.mode.pixel_clock[mode_t return real];
  alias pixel_clock_hz is nsl_dvi.mode.pixel_clock_hz[mode_t return natural];
  alias serial_clock_hz is nsl_dvi.mode.serial_clock_hz[mode_t return natural];
  alias refresh_rate is nsl_dvi.mode.refresh_rate[mode_t return real];
  alias h_total is nsl_dvi.mode.h_total[mode_t return natural];
  alias v_total is nsl_dvi.mode.v_total[mode_t return natural];
  alias mode_build is nsl_dvi.mode.mode_build[
    integer, integer, integer, integer,
    integer, integer, integer, integer,
    real, std_ulogic, std_ulogic return mode_t];
  alias mode_build_clocked is nsl_dvi.mode.mode_build_clocked[
    integer, integer, integer, integer,
    integer, integer, integer, integer,
    natural, real, std_ulogic, std_ulogic return mode_t];

  -- VIC 31,75
  constant mode_std_1920x1080p50_c: mode_t := nsl_dvi.mode.mode_std_1920x1080p50_c;
  -- VIC 19,68
  constant mode_std_1280x720p50_c: mode_t := nsl_dvi.mode.mode_std_1280x720p50_c;
  -- VIC 17,18
  constant mode_std_720x576p50_c: mode_t := nsl_dvi.mode.mode_std_720x576p50_c;
  -- VIC 16,76
  constant mode_std_1920x1080p60_c: mode_t := nsl_dvi.mode.mode_std_1920x1080p60_c;
  -- VIC 4,69
  constant mode_std_1280x720p60_c: mode_t := nsl_dvi.mode.mode_std_1280x720p60_c;
  -- VIC 1
  constant mode_std_640x480p5994_c: mode_t := nsl_dvi.mode.mode_std_640x480p5994_c;
  -- VIC 2,3
  constant mode_std_720x480p5994_c: mode_t := nsl_dvi.mode.mode_std_720x480p5994_c;

end package mode;
