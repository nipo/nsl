library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_time, nsl_simulation, work;
use nsl_dvi.terminal.all;
use work.func.all;

entity tb is
end tb;

-- The grandmaster status screen text, for a known state: every row
-- is compared to what the layout promises.
architecture arch of tb is

  constant clock_period_c : time := 10 ns;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal text_s : string(1 to screen_text_length_c);
  signal local_tick_s, gps_tick_s : std_ulogic;
  signal colors_s : label_color_vector(0 to screen_color_count_c-1);

  -- 2026-09-08 13:21:22 UTC, as PTP seconds with a 37 s offset.
  constant second_c : natural := 1788873719;

  -- The status row holds 13 characters of text, then rows of 16.
  constant status_length_c : natural := 13;

  function row(text : string; index : positive) return string is
    variable ret : string(1 to 16);
  begin
    ret := text(text'left + status_length_c + (index - 1) * 16
                to text'left + status_length_c + index * 16 - 1);
    return ret;
  end function;

  function status(text : string) return string is
    variable ret : string(1 to status_length_c);
  begin
    ret := text(text'left to text'left + status_length_c - 1);
    return ret;
  end function;

begin

  dut: work.func.screen_text
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      link_up_i => '1',
      gps_locked_i => '1',
      local_tick_i => local_tick_s,
      gps_tick_i => gps_tick_s,
      second_i => to_unsigned(second_c, 32),
      utc_offset_i => to_signed(37, 16),
      utc_offset_valid_i => '1',
      pps_offset_i => to_signed(-12, 31),
      aux_offset_i => to_signed(-1193, 31),
      freq_ppb_i => to_signed(332, 24),
      tacc_i => to_unsigned(14, 32),
      clock_class_i => to_unsigned(6, 8),
      dac_i => x"835",
      text_o => text_s,
      colors_o => colors_s
      );

  stim: process
    procedure tick(signal s : out std_ulogic; count : natural) is
    begin
      for i in 1 to count loop
        s <= '1';
        wait until rising_edge(clock_s);
        s <= '0';
        wait until rising_edge(clock_s);
      end loop;
    end procedure;

    procedure expect(index : positive; value : string) is
    begin
      assert row(text_s, index) = value
        report "row " & integer'image(index) & ": '" & row(text_s, index)
        & "', expected '" & value & "'"
        severity failure;
    end procedure;
  begin
    done_s(0) <= '0';
    local_tick_s <= '0';
    gps_tick_s <= '0';
    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    -- Three local seconds show the heart, two pulses leave the ring.
    tick(local_tick_s, 3);
    tick(gps_tick_s, 2);
    -- The calendar conversion takes a few hundred cycles.
    for i in 1 to 2000 loop
      wait until rising_edge(clock_s);
    end loop;
    for i in 1 to 7 loop
      report "row " & integer'image(i) & ": '" & row(text_s, i) & "'";
    end loop;
    assert status(text_s) = character'val(16#03#) & "LNK" & character'val(16#18#)
      & "GPS" & character'val(16#07#) & "PPS" & character'val(16#09#)
      report "status glyphs" severity failure;
    expect(1, "2026-09-08   UTC");
    expect(2, "13:21:22  TAI+37");
    expect(3, "PPS  -000012 ns ");
    expect(4, "AUX  -001193 ns ");
    expect(5, "SERVO +00332 ppb");
    expect(6, "TACC 000014 ns  ");
    assert row(text_s, 7)(1 to 12) = "CLS 006 DAC "
      report "row 7: '" & row(text_s, 7) & "'" severity failure;
    assert colors_s(screen_color_link_c) = x"02" and colors_s(screen_color_gps_c) = x"02"
      and colors_s(screen_color_pps_c) = x"02" and colors_s(screen_color_class_c) = x"02"
      and colors_s(screen_color_time_c) = x"05"
      report "status colors" severity failure;
    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 5,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
