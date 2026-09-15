library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_color, nsl_data, nsl_amba, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;

-- Walks a capture path into a stock AXI4-Stream FIFO.
--
-- A captured raster cannot be held back, arrives on the clock it was
-- recovered on, and anything downstream of it can wait and runs on a
-- clock of its own.  So something has to absorb both differences.  A pixel stream is
-- an AXI4-Stream, so nsl_amba's packet-dropping FIFO does it with no
-- pixel-specific code at all: it takes beats it cannot refuse on one
-- side, hands them out with backpressure on the other, and drops whole
-- packets rather than pieces of them when it runs out of room.
--
-- A packet here is a line, so what is checked is that lines come out
-- whole: never a piece of one, and never a line whose pixels sit
-- somewhere other than where they belong -- both while the FIFO is
-- kept drained, and after it has been made to overrun.
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
  signal sys_clock_s, sys_reset_n_s: std_ulogic;
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
  signal fifo_s: bus_t;
  signal overrun_s: std_ulogic;

  -- What comes out of the FIFO can be held back, which is the whole
  -- point of it being there.
  constant out_config_c: config_t := config(pixels => 1);

  signal accepting_s: std_ulogic := '1';
  signal overrun_seen_s: boolean := false;

  function bar_color(x: natural) return nsl_color.rgb.rgb24
  is
    constant index: natural := (x / bar_width_c) mod 8;
  begin
    return to_rgb24(rgb3_from_suv(std_ulogic_vector(to_unsigned(index, 3))));
  end function;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 2,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 7 ns,
      reset_duration(0) => 30 ns,
      reset_duration(1) => 30 ns,
      reset_n_o(0) => reset_n_s,
      reset_n_o(1) => sys_reset_n_s,
      clock_o(0) => clock_s,
      clock_o(1) => sys_clock_s,
      done_i => done_s
      );

  bars: nsl_video.pattern.rgb_color_bars
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

  -- The capturer ignores this, having no way to wait.
  rx_s.s <= accept(rx_config_c, ready => true);

  fifo: nsl_amba.stream_fifo.axi4_stream_async_packet_drop_fifo
    generic map(
      config_c => as_stream_config(out_config_c),
      -- Room for a few frames of this small a mode
      word_count_l2_c => 8,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_s,
      -- Written on the clock the raster arrives on, read on another
      clock_i(0) => clock_s,
      clock_i(1) => sys_clock_s,

      in_i => rx_s.m,
      in_o => open,

      out_i => fifo_s.s,
      out_o => fifo_s.m,

      overrun_o => overrun_s
      );

  fifo_s.s <= accept(out_config_c, ready => accepting_s = '1');

  -- overrun_o says what is happening now, so remember that it did
  overrun_latch: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if overrun_s = '1' then
        overrun_seen_s <= true;
      end if;
    end if;
  end process;

  main: process is
    variable color: nsl_color.rgb.rgb24;
    variable sof, last, eof, error: boolean;

    procedure take is
    begin
      loop
        wait until rising_edge(sys_clock_s);
        exit when is_valid(out_config_c, fifo_s.m)
          and is_ready(out_config_c, fifo_s.s);
      end loop;
      color := to_rgb24(out_config_c, pixel(out_config_c, fifo_s.m));
      sof := is_sof(out_config_c, fifo_s.m);
      last := is_last(out_config_c, fifo_s.m);
      eof := is_eof(out_config_c, fifo_s.m);
      error := is_error(out_config_c, fifo_s.m);
    end procedure;

    -- Walks one line, which has to arrive whole or not at all.
    procedure check_line(constant y: natural; constant msg: string) is
    begin
      for x in 0 to geometry_c.width-1
      loop
        if x /= 0 then
          take;
        end if;

        assert last = (x = geometry_c.width-1)
          report msg & ": line " & to_string(y) & " pixel " & to_string(x)
          & " disagrees on closing the line"
          severity failure;
        assert not error
          report msg & ": line " & to_string(y) & " came out marked in error"
          severity failure;
        assert color = bar_color(x)
          report msg & ": line " & to_string(y) & " pixel " & to_string(x)
          & " came out as "
          & to_hex_string(std_ulogic_vector(color.r))
          & to_hex_string(std_ulogic_vector(color.g))
          & to_hex_string(std_ulogic_vector(color.b))
          severity failure;
      end loop;
    end procedure;

    -- Takes beats until one opens a frame, which is where a whole
    -- frame can be walked from.
    procedure align is
    begin
      loop
        take;
        exit when sof;
      end loop;
    end procedure;

    procedure check_frame(constant frame: natural; constant msg: string) is
    begin
      for y in 0 to geometry_c.height-1
      loop
        if y /= 0 then
          take;
          assert not sof
            report msg & ": frame " & to_string(frame) & " opens again at line "
            & to_string(y)
            severity failure;
        end if;

        check_line(y, msg);

        assert eof = (y = geometry_c.height-1)
          report msg & ": frame " & to_string(frame) & " line " & to_string(y)
          & " disagrees on closing the frame"
          severity failure;
      end loop;
    end procedure;
  begin
    done_s <= "0";
    accepting_s <= '1';

    wait until sys_reset_n_s = '1' and reset_n_s = '1';

    -- Kept drained, nothing is dropped and whole frames come out
    align;
    for frame in 0 to 1
    loop
      if frame /= 0 then
        align;
      end if;
      check_frame(frame, "drained");
    end loop;

    assert not overrun_seen_s
      report "The FIFO overran while it was being kept drained"
      severity failure;

    -- Made to overrun, and what comes out is still whole lines in the
    -- right places, with some of them missing
    accepting_s <= '0';
    -- Long enough to hand it more than it can hold
    for i in 1 to h_total(mode_c) * v_total(mode_c) * 8
    loop
      wait until rising_edge(sys_clock_s);
    end loop;
    accepting_s <= '1';

    assert overrun_seen_s
      report "The FIFO did not report overrunning while it was held shut"
      severity failure;

    align;
    check_frame(0, "after overrun");

    done_s <= "1";
    wait;
  end process;

end architecture;
