library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_digilent, nsl_dvi, nsl_color;

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
  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : nsl_color.rgb.rgb24;

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
      clock_i_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s,

      pmod_io => j4_io
      );

  pattern: nsl_dvi.pattern.color_bars
    generic map(
      bar_width_c => 12
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sof_i => sof_s,
      sol_i => sol_s,
      pixel_ready_i => pixel_ready_s,
      pixel_valid_o => pixel_valid_s,
      pixel_o => pixel_s
      );

  -- Refresh heartbeat, toggles about twice a second
  heartbeat: process(clock_s)
  begin
    if rising_edge(clock_s) then
      if sof_s = '1' then
        frame_counter_s <= frame_counter_s + 1;
      end if;
    end if;
  end process;

  done_led_o <= frame_counter_s(frame_counter_s'left);

end arch;
