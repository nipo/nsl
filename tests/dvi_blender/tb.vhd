library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_simulation;
use nsl_dvi.blender.all;
use nsl_video.pixel_stream.all;

-- Pushes two known color-index sequences through
-- dvi_blender_color_key with uncorrelated stalls on both sources and
-- on the sink, and checks every output beat against a reference
-- blend. Position-dependent patterns catch any stream slip.
entity tb is
end entity;

architecture sim of tb is

  constant clock_period_c : time := 10 ns;

  constant color_count_l2_c : natural := 3;
  constant key_color_c : natural := 7;
  constant beat_count_c : natural := 512;

  constant config_c : config_t := config(pixels => 1,
                                         components => 1,
                                         component_bits => color_count_l2_c);

  subtype color_t is unsigned(color_count_l2_c-1 downto 0);

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal overlay_s, underlay_s, out_s : bus_t;

  signal overlay_ready_s, underlay_ready_s, color_valid_s : std_ulogic;
  signal color_s : color_t;

  signal overlay_done_s, underlay_done_s : boolean := false;
  signal done_s : boolean := false;

  function to_index_pixel(color: color_t) return pixel_t is
    variable ret: pixel_t := pixel_zero_c;
  begin
    ret(0) := resize(color, ret(0)'length);
    return ret;
  end function;

  function overlay_pattern(i: natural) return color_t is
  begin
    return to_unsigned((i * 5 + 3) mod 2**color_count_l2_c, color_count_l2_c);
  end function;

  function underlay_pattern(i: natural) return color_t is
  begin
    return to_unsigned((i * 3) mod 2**color_count_l2_c, color_count_l2_c);
  end function;

  function expected_pattern(i: natural) return color_t is
  begin
    if to_integer(overlay_pattern(i)) = key_color_c then
      return underlay_pattern(i);
    else
      return overlay_pattern(i);
    end if;
  end function;

begin

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 4 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  dut: dvi_blender_color_key
    generic map(
      config_c => config_c,
      key_color_c => key_color_c
      )
    port map(
      overlay_i => overlay_s.m,
      overlay_o => overlay_s.s,

      underlay_i => underlay_s.m,
      underlay_o => underlay_s.s,

      out_o => out_s.m,
      out_i => out_s.s
      );

  overlay_ready_s <= '1' when is_ready(config_c, overlay_s.s) else '0';
  underlay_ready_s <= '1' when is_ready(config_c, underlay_s.s) else '0';
  color_valid_s <= '1' when is_valid(config_c, out_s.m) else '0';
  color_s <= resize(pixel(config_c, out_s.m)(0), color_t'length);

  overlay_gen: process is
  begin
    overlay_s.m <= transfer(config_c, pixel_zero_c, valid => false);
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod 3 loop
        wait until falling_edge(clock_s);
      end loop;
      overlay_s.m <= transfer(config_c,
                              to_index_pixel(overlay_pattern(i)),
                              valid => true);
      wait until rising_edge(clock_s) and overlay_ready_s = '1';
      wait until falling_edge(clock_s);
      overlay_s.m <= transfer(config_c, pixel_zero_c, valid => false);
    end loop;

    overlay_done_s <= true;
    wait;
  end process;

  underlay_gen: process is
  begin
    underlay_s.m <= transfer(config_c, pixel_zero_c, valid => false);
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod 5 loop
        wait until falling_edge(clock_s);
      end loop;
      underlay_s.m <= transfer(config_c,
                               to_index_pixel(underlay_pattern(i)),
                               valid => true);
      wait until rising_edge(clock_s) and underlay_ready_s = '1';
      wait until falling_edge(clock_s);
      underlay_s.m <= transfer(config_c, pixel_zero_c, valid => false);
    end loop;

    underlay_done_s <= true;
    wait;
  end process;

  sink: process is
    variable expected : color_t;
  begin
    out_s.s <= accept(config_c, ready => false);
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod 4 loop
        wait until falling_edge(clock_s);
      end loop;
      out_s.s <= accept(config_c, ready => true);
      wait until rising_edge(clock_s) and color_valid_s = '1';
      expected := expected_pattern(i);
      assert color_s = expected
        report "Beat " & integer'image(i)
        & " expected " & integer'image(to_integer(expected))
        & ", got " & integer'image(to_integer(color_s))
        severity failure;
      wait until falling_edge(clock_s);
      out_s.s <= accept(config_c, ready => false);
    end loop;

    for i in 1 to 4 loop
      wait until rising_edge(clock_s);
    end loop;

    assert overlay_done_s and underlay_done_s
      report "Sources did not consume the whole sequence"
      severity failure;

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 ms;
    assert false
      report "Timeout"
      severity failure;
  end process;

end architecture;
