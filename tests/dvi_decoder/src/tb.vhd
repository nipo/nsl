library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_color, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;

-- Sends colour bars out as a DVI signal and reads them back through
-- sink_stream_decoder, checking the periods the decoder reports and
-- the pixels it hands out.  A DVI link states no preamble and no
-- guard band, so video here starts on the first symbol that is not a
-- control one.
entity tb is
end entity;

architecture arch of tb is

  constant mode_c: mode_t := mode_build(16, 10, 2, 4,
                                        4, 5, 1, 2,
                                        60.0, '1', '1');
  constant geometry_c: geometry_t := geometry(mode_c);
  constant config_c: config_t := config(pixels => 1);
  constant bar_width_c: natural := 4;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal pixels_s: bus_t;
  signal synced_s: std_ulogic;
  signal tmds_s: nsl_dvi.dvi.symbol_vector_t;

  signal period_s: nsl_dvi.dvi.period_t;
  signal decoded_s: nsl_data.bytestream.byte_string(0 to 2);
  signal hsync_s, vsync_s: std_ulogic;

  function bar_color(x: natural) return nsl_color.rgb.rgb24
  is
    constant index: natural := (x / bar_width_c) mod 8;
  begin
    return to_rgb24(rgb3_from_suv(std_ulogic_vector(to_unsigned(index, 3))));
  end function;

  -- DVI carries blue on channel 0, green on 1, red on 2.
  function as_rgb24(channels: nsl_data.bytestream.byte_string) return nsl_color.rgb.rgb24
  is
  begin
    return nsl_color.rgb.rgb24'(r => unsigned(channels(2)),
                                g => unsigned(channels(1)),
                                b => unsigned(channels(0)));
  end function;

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

  bars: nsl_video.pattern.rgb_color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => config_c,
      bar_width_c => bar_width_c
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

      v_fp_m1_i => v_fp_m1(mode_c),
      v_sync_m1_i => v_sync_m1(mode_c),
      v_bp_m1_i => v_bp_m1(mode_c),
      v_act_m1_i => v_act_m1(mode_c),

      h_fp_m1_i => h_fp_m1(mode_c),
      h_sync_m1_i => h_sync_m1(mode_c),
      h_bp_m1_i => h_bp_m1(mode_c),
      h_act_m1_i => h_act_m1(mode_c),

      vsync_i => mode_c.v.sync,
      hsync_i => mode_c.h.sync,

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
      pixel_o => decoded_s,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => open,
      di_data_o => open
      );

  main: process is
    variable c: nsl_color.rgb.rgb24;
    variable active: natural;

    -- Walks one frame, from the vertical sync that opens it to the
    -- last pixel of its last line.
    procedure check_frame(constant frame: natural) is
    begin
      wait until rising_edge(clock_s)
        and period_s = PERIOD_CONTROL and vsync_s = '1';
      wait until rising_edge(clock_s) and vsync_s = '0';

      for y in 0 to geometry_c.height-1
      loop
        -- Blanking before the line, syncs and nothing else
        while period_s = PERIOD_CONTROL
        loop
          wait until rising_edge(clock_s);
        end loop;

        assert period_s = PERIOD_VIDEO_DATA
          report "Frame " & to_string(frame) & " line " & to_string(y)
          & " opens on a period a DVI link should not state"
          severity failure;

        for x in 0 to geometry_c.width-1
        loop
          assert period_s = PERIOD_VIDEO_DATA
            report "Frame " & to_string(frame) & " pixel " & to_string(x)
            & "," & to_string(y) & " is not in a video period"
            severity failure;

          c := as_rgb24(decoded_s);
          assert c = bar_color(x)
            report "Frame " & to_string(frame) & " pixel " & to_string(x)
            & "," & to_string(y) & " came off the wire as "
            & to_hex_string(std_ulogic_vector(c.r))
            & to_hex_string(std_ulogic_vector(c.g))
            & to_hex_string(std_ulogic_vector(c.b))
            severity failure;

          wait until rising_edge(clock_s);
        end loop;

        assert period_s = PERIOD_CONTROL
          report "Frame " & to_string(frame) & " line " & to_string(y)
          & " runs past the pixels it holds"
          severity failure;
      end loop;
    end procedure;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s) and synced_s = '1';

    for frame in 0 to 1
    loop
      check_frame(frame);
    end loop;

    -- Horizontal sync sits in the blanking, and a whole frame holds
    -- as many of them as it holds lines
    active := 0;
    for i in 1 to h_total(mode_c) * v_total(mode_c)
    loop
      wait until rising_edge(clock_s);
      if period_s = PERIOD_VIDEO_DATA then
        active := active + 1;
      end if;
      assert not (period_s = PERIOD_VIDEO_DATA and hsync_s = '1')
        report "Horizontal sync overlaps video data"
        severity failure;
    end loop;

    assert active = geometry_c.width * geometry_c.height
      report "A frame holds " & to_string(active) & " video symbols, expected "
      & to_string(geometry_c.width * geometry_c.height)
      severity failure;

    done_s <= "1";
    wait;
  end process;

end architecture;
