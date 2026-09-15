library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_video, nsl_simulation, nsl_data;
use nsl_video.mode.all;
use nsl_data.text.all;

entity tb is
end entity;

architecture arch of tb is
begin

  main: process
    variable m : mode_t;
  begin
    -- A broadcast mode states its frame rate, and the geometry gives
    -- the clock back exactly

    m := mode_std_1280x720p50_c;
    assert h_total(m) = 1980 and v_total(m) = 750
      report "Bad 720p50 geometry"
      severity failure;
    assert pixel_clock_hz(m) = 74_250_000
      report "Bad 720p50 pixel clock: " & to_string(pixel_clock_hz(m))
      severity failure;
    assert serial_clock_hz(m) = 371_250_000
      report "Bad 720p50 serial clock"
      severity failure;
    assert abs(refresh_rate(m) - 50.0) < 0.001
      report "Bad 720p50 refresh rate"
      severity failure;

    assert pixel_clock_hz(mode_std_1920x1080p60_c) = 148_500_000
      report "Bad 1080p60 pixel clock"
      severity failure;
    assert pixel_clock_hz(mode_std_720x480p5994_c) = 27_000_000
      report "Bad 480p59.94 pixel clock"
      severity failure;

    -- A computer mode states its clock, and the frame rate is what
    -- that clock gives, not the rate the mode is known by

    m := mode_std_1024x768p60_c;
    assert h_total(m) = 1344 and v_total(m) = 806
      report "Bad XGA geometry"
      severity failure;
    assert pixel_clock_hz(m) = 65_000_000
      report "Bad XGA pixel clock: " & to_string(pixel_clock_hz(m))
      severity failure;
    assert m.fps = 60.0
      report "XGA is not known as a 60Hz mode"
      severity failure;
    assert abs(refresh_rate(m) - 60.0042) < 0.001
      report "Bad XGA refresh rate: " & to_string(refresh_rate(m))
      severity failure;
    -- Deriving the clock from the nominal rate would have missed by
    -- 13kHz, which an exact-or-fail PLL config would refuse
    assert natural(round(m.fps * real(h_total(m)) * real(v_total(m))))
      /= pixel_clock_hz(m)
      report "XGA clock happens to match its nominal rate"
      severity failure;

    -- VIC 1 likewise states 25.175MHz, which its frame rate misses
    assert pixel_clock_hz(mode_std_640x480p5994_c) = 25_175_000
      report "Bad VIC 1 pixel clock"
      severity failure;

    -- Timings come out as the counters want them, less one

    m := mode_std_1280x720p50_c;
    assert h_fp_m1(m, 9) = to_unsigned(439, 9)
      and h_sync_m1(m, 6) = to_unsigned(39, 6)
      and h_bp_m1(m, 8) = to_unsigned(219, 8)
      and h_act_m1(m, 11) = to_unsigned(1279, 11)
      report "Bad horizontal timings"
      severity failure;
    assert v_fp_m1(m, 3) = to_unsigned(4, 3)
      and v_sync_m1(m, 3) = to_unsigned(4, 3)
      and v_bp_m1(m, 5) = to_unsigned(19, 5)
      and v_act_m1(m, 10) = to_unsigned(719, 10)
      report "Bad vertical timings"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
