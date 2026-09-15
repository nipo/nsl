library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_color, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;

-- Sends a mode out as a DVI signal, reads it back, and measures it.
--
-- What the encoder emits from a mode is by definition that mode, so
-- the measurement has to come back equal to the mode's own timings.
-- The encoder takes its timings on ports, so one instance walks
-- several modes and the measurement has to follow each of them.
entity tb is
end entity;

architecture arch of tb is

  -- Modes share their active area, since the frame generator is built
  -- around one, and differ in blanking and in sync polarity.
  constant geometry_c: geometry_t := geometry(16, 4);
  constant config_c: config_t := config(pixels => 1);
  constant count_width_c: natural := 8;

  type mode_vector is array(natural range <>) of mode_t;
  constant modes_c: mode_vector(0 to 2) := (
    mode_build(16, 10, 2, 4, 4, 5, 1, 2, 60.0, '1', '1'),
    -- The same frame, both syncs the other way up
    mode_build(16, 10, 2, 4, 4, 5, 1, 2, 60.0, '0', '0'),
    -- Wider blanking, and one sync each way
    mode_build(16, 20, 5, 6, 4, 7, 2, 3, 60.0, '1', '0')
    );

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal pixels_s: bus_t;
  signal synced_s: std_ulogic;
  signal tmds_s: nsl_dvi.dvi.symbol_vector_t;

  signal period_s: nsl_dvi.dvi.period_t;
  signal hsync_s, vsync_s, de_s: std_ulogic;

  signal timings_s: nsl_video.mode.timings_t;
  signal timings_valid_s: std_ulogic;

  signal mode_index_s: natural range modes_c'range := 0;

  -- The encoder takes its timings on ports, so they come from signals
  -- the selected mode drives rather than from constants.
  subtype timing_t is unsigned(count_width_c-1 downto 0);
  signal h_fp_s, h_sync_s, h_bp_s, h_act_s: timing_t;
  signal v_fp_s, v_sync_s, v_bp_s, v_act_s: timing_t;
  signal hsync_pol_s, vsync_pol_s: std_ulogic;

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

  h_fp_s <= h_fp_m1(modes_c(mode_index_s), count_width_c);
  h_sync_s <= h_sync_m1(modes_c(mode_index_s), count_width_c);
  h_bp_s <= h_bp_m1(modes_c(mode_index_s), count_width_c);
  h_act_s <= h_act_m1(modes_c(mode_index_s), count_width_c);
  v_fp_s <= v_fp_m1(modes_c(mode_index_s), count_width_c);
  v_sync_s <= v_sync_m1(modes_c(mode_index_s), count_width_c);
  v_bp_s <= v_bp_m1(modes_c(mode_index_s), count_width_c);
  v_act_s <= v_act_m1(modes_c(mode_index_s), count_width_c);
  hsync_pol_s <= modes_c(mode_index_s).h.sync;
  vsync_pol_s <= modes_c(mode_index_s).v.sync;

  bars: nsl_video.pattern.rgb_color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => config_c,
      bar_width_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      out_o => pixels_s.m,
      out_i => pixels_s.s
      );

  encoder: nsl_dvi.encoder.dvi_10_encoder
    generic map(
      config_c => config_c
      )
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      v_fp_m1_i => v_fp_s,
      v_sync_m1_i => v_sync_s,
      v_bp_m1_i => v_bp_s,
      v_act_m1_i => v_act_s,

      h_fp_m1_i => h_fp_s,
      h_sync_m1_i => h_sync_s,
      h_bp_m1_i => h_bp_s,
      h_act_m1_i => h_act_s,

      vsync_i => vsync_pol_s,
      hsync_i => hsync_pol_s,

      pixel_i => pixels_s.m,
      pixel_o => pixels_s.s,
      synced_o => synced_s,

      tmds_o => tmds_s
      );

  decoder: nsl_dvi.decoder.sink_stream_decoder
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      tmds_i => tmds_s,

      period_o => period_s,
      pixel_o => open,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => open,
      di_data_o => open
      );

  de_s <= '1' when period_s = PERIOD_VIDEO_DATA else '0';

  measurer: nsl_video.raster.raster_measurer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      de_i => de_s,
      hsync_i => hsync_s,
      vsync_i => vsync_s,

      timings_o => timings_s,
      valid_o => timings_valid_s
      );

  main: process is
    variable expected: nsl_video.mode.timings_t;

    procedure report_axis(constant name: string;
                          constant got, want: axis_timings_t) is
    begin
      assert got = want
        report name & " measured active " & to_string(to_integer(got.active))
        & " blank " & to_string(to_integer(got.blank))
        & " off " & to_string(to_integer(got.off))
        & " width " & to_string(to_integer(got.width))
        & " sync " & to_string(got.sync)
        & ", expected active " & to_string(to_integer(want.active))
        & " blank " & to_string(to_integer(want.blank))
        & " off " & to_string(to_integer(want.off))
        & " width " & to_string(to_integer(want.width))
        & " sync " & to_string(want.sync)
        severity failure;
    end procedure;

    -- Waits for the measurement to settle on what the mode states.  A
    -- mode change takes a couple of frames to walk out of the
    -- measurement, so a few are allowed before giving up.
    procedure await_mode(constant index: natural) is
      constant mode: mode_t := modes_c(index);
      constant want: nsl_video.mode.timings_t := timings(mode);
      constant frame_c: natural := h_total(mode) * v_total(mode);
    begin
      for i in 1 to frame_c * 6
      loop
        wait until rising_edge(clock_s);
        exit when timings_valid_s = '1' and timings_s = want;
      end loop;

      assert timings_valid_s = '1'
        report "Mode " & to_string(index) & " never measured as settled"
        severity failure;

      report_axis("Mode " & to_string(index) & " horizontal",
                  timings_s.h, want.h);
      report_axis("Mode " & to_string(index) & " vertical",
                  timings_s.v, want.v);
    end procedure;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    assert timings_valid_s = '0'
      report "A measurement is offered before a frame went by"
      severity failure;

    for index in modes_c'range
    loop
      mode_index_s <= index;
      await_mode(index);

      -- and it holds, rather than being a frame that happened to
      -- agree once
      for i in 1 to h_total(modes_c(index)) * v_total(modes_c(index)) * 2
      loop
        wait until rising_edge(clock_s);
        assert timings_valid_s = '1' and timings_s = timings(modes_c(index))
          report "Mode " & to_string(index) & " measurement did not hold"
          severity failure;
      end loop;
    end loop;

    done_s <= "1";
    wait;
  end process;

end architecture;
