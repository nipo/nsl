library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_simulation;
use nsl_dvi.blender.all;

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

  subtype color_t is unsigned(color_count_l2_c-1 downto 0);

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal overlay_ready_s, overlay_valid_s : std_ulogic;
  signal underlay_ready_s, underlay_valid_s : std_ulogic;
  signal color_ready_s, color_valid_s : std_ulogic;
  signal overlay_color_s, underlay_color_s, color_s : color_t;

  signal overlay_done_s, underlay_done_s : boolean := false;
  signal done_s : boolean := false;

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
      color_count_l2_c => color_count_l2_c,
      key_color_c => key_color_c
      )
    port map(
      overlay_ready_o => overlay_ready_s,
      overlay_valid_i => overlay_valid_s,
      overlay_color_i => overlay_color_s,

      underlay_ready_o => underlay_ready_s,
      underlay_valid_i => underlay_valid_s,
      underlay_color_i => underlay_color_s,

      color_ready_i => color_ready_s,
      color_valid_o => color_valid_s,
      color_o => color_s
      );

  overlay_gen: process is
  begin
    overlay_valid_s <= '0';
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod 3 loop
        wait until falling_edge(clock_s);
      end loop;
      overlay_color_s <= overlay_pattern(i);
      overlay_valid_s <= '1';
      wait until rising_edge(clock_s) and overlay_ready_s = '1';
      wait until falling_edge(clock_s);
      overlay_valid_s <= '0';
    end loop;

    overlay_done_s <= true;
    wait;
  end process;

  underlay_gen: process is
  begin
    underlay_valid_s <= '0';
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod 5 loop
        wait until falling_edge(clock_s);
      end loop;
      underlay_color_s <= underlay_pattern(i);
      underlay_valid_s <= '1';
      wait until rising_edge(clock_s) and underlay_ready_s = '1';
      wait until falling_edge(clock_s);
      underlay_valid_s <= '0';
    end loop;

    underlay_done_s <= true;
    wait;
  end process;

  sink: process is
    variable expected : color_t;
  begin
    color_ready_s <= '0';
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod 4 loop
        wait until falling_edge(clock_s);
      end loop;
      color_ready_s <= '1';
      wait until rising_edge(clock_s) and color_valid_s = '1';
      expected := expected_pattern(i);
      assert color_s = expected
        report "Beat " & integer'image(i)
        & " expected " & integer'image(to_integer(expected))
        & ", got " & integer'image(to_integer(color_s))
        severity failure;
      wait until falling_edge(clock_s);
      color_ready_s <= '0';
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
