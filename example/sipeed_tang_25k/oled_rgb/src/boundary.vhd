library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_digilent, nsl_color, nsl_video,
  nsl_solomonsystech;

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;

    j4_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;
  constant geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(nsl_solomonsystech.ssd1331.max_width_c,
                              nsl_solomonsystech.ssd1331.max_height_c);
  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);

  signal pixel_s : nsl_video.pixel_stream.bus_t;
  signal synced_s, frame_end_s : std_ulogic;

  signal frame_counter_s : unsigned(5 downto 0) := (others => '0');

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

  display: nsl_digilent.pmod_oled_rgb.pmod_oled_rgb_driver
    generic map(
      clock_i_hz_c => clk_hz_c,
      config_c => pixel_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      pixel_i => pixel_s.m,
      pixel_o => pixel_s.s,
      synced_o => synced_s,

      pmod_io => j4_io
      );

  pattern: nsl_video.pattern.rgb_color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => pixel_config_c,
      bar_width_c => 12
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      out_o => pixel_s.m,
      out_i => pixel_s.s
      );

  frame_end_s <= '1' when nsl_video.pixel_stream.is_taken(pixel_config_c, pixel_s.m, pixel_s.s)
                 and nsl_video.pixel_stream.is_eof(pixel_config_c, pixel_s.m)
                 else '0';

  -- Refresh heartbeat, toggles about twice a second
  heartbeat: process(clock_s)
  begin
    if rising_edge(clock_s) then
      if frame_end_s = '1' then
        frame_counter_s <= frame_counter_s + 1;
      end if;
    end if;
  end process;

  done_led_o <= frame_counter_s(frame_counter_s'left);

end arch;
