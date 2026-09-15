library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_dvi, nsl_video, nsl_sipeed,
  nsl_digilent, nsl_data;
use nsl_data.bytestream.all;
use nsl_video.mode.all;
use nsl_clocking.pll.all;

-- Colour bars out of J5, and nothing else.
--
-- What this answers is whether J5 can drive this Pmod at all: there is
-- no receiver, no overlay and no stream here, so anything wrong is in
-- the transmitter, the pads or the wiring.
--
-- The bars are chosen so that each channel stands alone somewhere.
-- Blue, green and red each appear by themselves, and the three pairs
-- appear too, so a channel that never arrives says which one it is
-- rather than only that something is wrong.
--
-- 25MHz rather than the 25.175MHz the mode names, because it divides
-- from the board clock and a screen does not mind sixty frames being
-- fifty nine and a half.
entity boundary is
  port (
    clk_i : in std_ulogic;

    ready_led_o: out std_ulogic;
    done_led_o: out std_ulogic;

    -- Not used.  Here to say whether J4 being claimed as LVDS inputs
    -- is what stops J5 driving as LVCMOS outputs: two of J5's four
    -- output pads sit among J4's.
    dvi_ck_i: in std_ulogic;
    dvi_d_i: in std_ulogic_vector(0 to 2);

    j5_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;

  constant mode_c : mode_t := mode_build_clocked(
    640, 160, 16, 96,
    480, 45, 10, 2,
    25_000_000, 60.0, '0', '0');

  constant pll_config_c : pll_config_t := pll_config(
    input_hz => clk_hz_c,
    o0 => pll_output(serial_clock_hz(mode_c)),
    o1 => pll_output(pixel_clock_hz(mode_c)));

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to pll_config_c.output_count-1);
  signal pixel_clock_s, serial_clock_s : std_ulogic;
  signal pll_locked_s, pixel_reset_n_s : std_ulogic;

  signal h_s : unsigned(10 downto 0);
  signal v_s : unsigned(10 downto 0);
  signal period_s : nsl_dvi.dvi.period_t;
  signal hsync_s, vsync_s : std_ulogic;
  signal pixel_s : byte_string(0 to 2);
  signal beat_s : unsigned(24 downto 0);
  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  constant h_total_c : natural := mode_c.h.active + mode_c.h.blank;
  constant v_total_c : natural := mode_c.v.active + mode_c.v.blank;
  constant h_sync_start_c : natural := mode_c.h.active + mode_c.h.off;
  constant h_sync_end_c : natural := h_sync_start_c + mode_c.h.width;
  constant v_sync_start_c : natural := mode_c.v.active + mode_c.v.off;
  constant v_sync_end_c : natural := v_sync_start_c + mode_c.v.width;

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => internal_reset_n_s
      );

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => internal_reset_n_s,
      data_o => reset_n_s
      );

  video_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      clock_o => pll_clock_s,
      locked_o => pll_locked_s
      );

  serial_clock_s <= pll_clock_s(0);
  pixel_clock_s <= pll_clock_s(1);

  pixel_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => pixel_clock_s,
      data_i => pll_locked_s,
      data_o => pixel_reset_n_s
      );

  raster: process(pixel_clock_s, pixel_reset_n_s) is
  begin
    if rising_edge(pixel_clock_s) then
      if h_s = h_total_c - 1 then
        h_s <= (others => '0');

        if v_s = v_total_c - 1 then
          v_s <= (others => '0');
        else
          v_s <= v_s + 1;
        end if;
      else
        h_s <= h_s + 1;
      end if;

      beat_s <= beat_s + 1;
    end if;

    if pixel_reset_n_s = '0' then
      h_s <= (others => '0');
      v_s <= (others => '0');
      beat_s <= (others => '0');
    end if;
  end process;

  period_s <= nsl_dvi.dvi.PERIOD_VIDEO_DATA
              when h_s < mode_c.h.active and v_s < mode_c.v.active
              else nsl_dvi.dvi.PERIOD_CONTROL;

  -- A sync pulse states the level the mode names; the rest of the line
  -- states the other one.
  hsync_s <= mode_c.h.sync
             when h_s >= h_sync_start_c and h_s < h_sync_end_c
             else not mode_c.h.sync;
  vsync_s <= mode_c.v.sync
             when v_s >= v_sync_start_c and v_s < v_sync_end_c
             else not mode_c.v.sync;

  -- Bars of 64, in an order that puts each channel alone somewhere:
  -- black, blue, green, cyan, red, magenta, yellow, white.  A channel
  -- that never arrives leaves its own bar black and takes the colour
  -- out of the two it shares.
  bars: process(h_s) is
    variable bar: unsigned(2 downto 0);
  begin
    bar := h_s(8 downto 6);

    pixel_s(0) <= (others => bar(0));
    pixel_s(1) <= (others => bar(1));
    pixel_s(2) <= (others => bar(2));
  end process;

  encoder: nsl_dvi.encoder.source_stream_encoder
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,

      period_i => period_s,
      pixel_i => pixel_s,
      hsync_i => hsync_s,
      vsync_i => vsync_s,

      tmds_o => tmds_s
      );

  driver: nsl_sipeed.pmod_dvi.pmod_dvi_output
    port map(
      reset_n_i => pixel_reset_n_s,
      pixel_clock_i => pixel_clock_s,
      serial_clock_i => serial_clock_s,

      tmds_i => tmds_s,

      pmod_o => j5_io
      );

  -- Kept alive so the inputs are not optimised away
  ready_led_o <= pll_locked_s xor dvi_ck_i xor dvi_d_i(0)
                 xor dvi_d_i(1) xor dvi_d_i(2);
  done_led_o <= beat_s(beat_s'left);

end arch;
