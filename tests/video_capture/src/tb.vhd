library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_color, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;

-- Walks a whole capture path: colour bars go out as a DVI signal, and
-- come back as a pixel stream through the decoder, the measurer and
-- the capturer.
--
-- Nothing here knows what mode is being sent.  The decoder recovers
-- the raster, the measurer works out the frame from the syncs, and the
-- capturer turns it into a stream -- so what is checked is that the
-- bars come back out the far end whole, framed, and in the right
-- places.
entity tb is
end entity;

architecture arch of tb is

  constant mode_c: mode_t := mode_build(16, 10, 2, 4,
                                        4, 5, 1, 2,
                                        60.0, '1', '1');
  constant geometry_c: geometry_t := geometry(mode_c);
  constant bar_width_c: natural := 4;

  -- What goes out has backpressure, what comes back cannot be held
  -- back at all.
  constant tx_config_c: config_t := config(pixels => 1);
  constant rx_config_c: config_t := config(pixels => 1, ready => false);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal tx_s: bus_t;
  signal synced_s: std_ulogic;
  signal tmds_s: nsl_dvi.dvi.symbol_vector_t;

  signal period_s: nsl_dvi.dvi.period_t;
  signal decoded_s: nsl_data.bytestream.byte_string(0 to 2);
  signal hsync_s, vsync_s, de_s: std_ulogic;
  signal rx_pixel_s: pixel_t;

  signal timings_s: nsl_video.mode.timings_t;
  signal timings_valid_s: std_ulogic;

  signal rx_s: bus_t;

  function bar_color(x: natural) return nsl_color.rgb.rgb24
  is
    constant index: natural := (x / bar_width_c) mod 8;
  begin
    return to_rgb24(rgb3_from_suv(std_ulogic_vector(to_unsigned(index, 3))));
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

  bars: nsl_dvi.pattern.color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => tx_config_c,
      bar_width_c => bar_width_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      out_o => tx_s.m,
      out_i => tx_s.s
      );

  encoder: nsl_dvi.encoder.dvi_10_encoder
    generic map(
      config_c => tx_config_c
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

      pixel_i => tx_s.m,
      pixel_o => tx_s.s,
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

  de_s <= '1' when period_s = PERIOD_VIDEO_DATA else '0';

  -- DVI carries blue on channel 0, green on 1, red on 2, and the
  -- stream names its components the way the colourspace does.
  rx_pixel_s <= pixel_t'(
    0 => resize(unsigned(decoded_s(2)), max_component_bits_c),
    1 => resize(unsigned(decoded_s(1)), max_component_bits_c),
    2 => resize(unsigned(decoded_s(0)), max_component_bits_c),
    others => (others => '0'));

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

  capturer: nsl_video.raster.pixel_stream_capturer
    generic map(
      config_c => rx_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      de_i => de_s,
      vsync_i => vsync_s,
      pixel_i => rx_pixel_s,

      timings_i => timings_s,
      timings_valid_i => timings_valid_s,

      out_o => rx_s.m,
      out_i => rx_s.s
      );

  rx_s.s <= accept(rx_config_c, ready => true);

  main: process is
    variable color: nsl_color.rgb.rgb24;
    variable sof, last, eof, error: boolean;

    -- Takes the next beat the capturer offers.  It cannot be held
    -- back, so this only watches.
    procedure take is
    begin
      wait until rising_edge(clock_s) and is_valid(rx_config_c, rx_s.m);
      color := to_rgb24(rx_config_c, pixel(rx_config_c, rx_s.m));
      sof := is_sof(rx_config_c, rx_s.m);
      last := is_last(rx_config_c, rx_s.m);
      eof := is_eof(rx_config_c, rx_s.m);
      error := is_error(rx_config_c, rx_s.m);
    end procedure;

    procedure check_pixel(constant x, y, frame: natural) is
    begin
      assert sof = (x = 0 and y = 0)
        report "Frame " & to_string(frame) & " pixel " & to_string(x)
        & "," & to_string(y) & " disagrees on opening the frame"
        severity failure;
      assert last = (x = geometry_c.width-1)
        report "Frame " & to_string(frame) & " pixel " & to_string(x)
        & "," & to_string(y) & " disagrees on closing the line"
        severity failure;
      assert eof = (x = geometry_c.width-1 and y = geometry_c.height-1)
        report "Frame " & to_string(frame) & " pixel " & to_string(x)
        & "," & to_string(y) & " disagrees on closing the frame"
        severity failure;
      assert not error
        report "Frame " & to_string(frame) & " line " & to_string(y)
        & " came back marked in error"
        severity failure;
      assert color = bar_color(x)
        report "Frame " & to_string(frame) & " pixel " & to_string(x)
        & "," & to_string(y) & " came back as "
        & to_hex_string(std_ulogic_vector(color.r))
        & to_hex_string(std_ulogic_vector(color.g))
        & to_hex_string(std_ulogic_vector(color.b))
        severity failure;
    end procedure;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    assert not is_valid(rx_config_c, rx_s.m)
      report "A beat came out before the link settled"
      severity failure;

    -- The capturer offers nothing until the measurement settled, so
    -- the first beat that turns up opens a frame.
    take;
    assert sof
      report "The first beat out of the capturer does not open a frame"
      severity failure;

    for frame in 0 to 2
    loop
      for y in 0 to geometry_c.height-1
      loop
        for x in 0 to geometry_c.width-1
        loop
          if not (frame = 0 and x = 0 and y = 0) then
            take;
          end if;
          check_pixel(x, y, frame);
        end loop;
      end loop;
    end loop;

    done_s <= "1";
    wait;
  end process;

end architecture;
