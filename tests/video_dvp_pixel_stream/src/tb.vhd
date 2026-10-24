library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_color, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;

-- Drives a DVP bus through dvp_receiver and dvp_to_pixel_stream and
-- checks the framing and pixels that come out.
--
-- Every word on the bus is a function of its frame, line and
-- column, so a beat out tells where it came from.  The bus goes
-- through: lines before any frame sync, whole frames, a short and a
-- long line, a line past the frame height, frames cut short between
-- lines and inside a line, and a frame stalled by the stream ready
-- going low long enough to lose a word.
entity tb is
end entity;

architecture arch of tb is

  constant geometry_c: geometry_t := geometry(4, 3);
  constant config_c: config_t := config(pixels => 1, component_bits => 8);

  -- One line expected out of the stream: where its words came from,
  -- how many beats it holds, and what it closes with.
  type line_t is
  record
    frame, y, length: natural;
    sof, eof, error: boolean;
  end record;
  type line_vector is array (natural range <>) of line_t;

  constant expected_c: line_vector := (
    -- Whole frame
    (1, 0, 4, true, false, false),
    (1, 1, 4, false, false, false),
    (1, 2, 4, false, true, false),
    -- Short line, long line cropped, extra line dropped
    (2, 0, 4, true, false, false),
    (2, 1, 2, false, false, true),
    (2, 2, 4, false, true, false),
    -- Cut short after a whole line
    (3, 0, 4, true, false, false),
    (3, 1, 4, false, true, true),
    -- Cut short inside a line
    (4, 0, 4, true, false, false),
    (4, 1, 2, false, true, true),
    -- Whole frame
    (5, 0, 4, true, false, false),
    (5, 1, 4, false, false, false),
    (5, 2, 4, false, true, false),
    -- Stalled in line 1, aborted
    (6, 0, 4, true, false, false),
    (6, 1, 3, false, true, true),
    -- Whole frame
    (7, 0, 4, true, false, false),
    (7, 1, 4, false, false, false),
    (7, 2, 4, false, true, false)
    );

  -- Frame and line during which ready goes low, right after the
  -- first beat of the line is taken.
  constant stall_frame_c: natural := 6;
  constant stall_y_c: natural := 1;
  constant stall_cycles_c: natural := 12;
  constant expected_overflows_c: natural := 1;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);
  signal bus_done_s: boolean := false;

  signal vsync_s, href_s: std_ulogic;
  signal bus_data_s: std_ulogic_vector(7 downto 0);

  signal word_valid_s, word_sof_s, word_sol_s: std_ulogic;
  signal word_s: std_ulogic_vector(15 downto 0);

  signal stream_s: bus_t;
  signal ready_s: boolean;
  signal overflow_s: std_ulogic;

  function word(frame, y, x: natural) return std_ulogic_vector
  is
  begin
    return std_ulogic_vector(to_unsigned((frame * 7919 + y * 1237 + x * 331 + 17) mod 65536, 16));
  end function;

  function rgb565_color(w: std_ulogic_vector(15 downto 0)) return rgb24
  is
    variable ret: rgb24;
  begin
    ret.r := unsigned(w(15 downto 11) & w(15 downto 13));
    ret.g := unsigned(w(10 downto 5) & w(10 downto 9));
    ret.b := unsigned(w(4 downto 0) & w(4 downto 2));
    return ret;
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

  receiver: nsl_video.dvp.dvp_receiver
    port map(
      pclk_i => clock_s,
      reset_n_i => reset_n_s,

      vsync_i => vsync_s,
      href_i => href_s,
      data_i => bus_data_s,

      valid_o => word_valid_s,
      sof_o => word_sof_s,
      sol_o => word_sol_s,
      data_o => word_s
      );

  dut: nsl_video.dvp.dvp_to_pixel_stream
    generic map(
      config_c => config_c,
      format_c => nsl_video.dvp.FORMAT_RGB565,
      geometry_c => geometry_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      valid_i => word_valid_s,
      sof_i => word_sof_s,
      sol_i => word_sol_s,
      data_i => word_s,

      out_o => stream_s.m,
      out_i => stream_s.s,

      overflow_o => overflow_s
      );

  stream_s.s <= accept(config_c, ready => ready_s);

  dvp_bus: process is
    procedure cycles(constant n: natural) is
    begin
      for i in 1 to n
      loop
        wait until falling_edge(clock_s);
      end loop;
    end procedure;

    procedure frame_sync is
    begin
      vsync_s <= '1';
      cycles(4);
      vsync_s <= '0';
      cycles(6);
    end procedure;

    procedure line(constant frame, y, length: natural) is
      variable w: std_ulogic_vector(15 downto 0);
    begin
      for x in 0 to length-1
      loop
        w := word(frame, y, x);
        href_s <= '1';
        bus_data_s <= w(15 downto 8);
        cycles(1);
        bus_data_s <= w(7 downto 0);
        cycles(1);
      end loop;
      href_s <= '0';
      bus_data_s <= (others => '-');
      cycles(8);
    end procedure;

    procedure whole_frame(constant frame: natural) is
    begin
      frame_sync;
      for y in 0 to geometry_c.height-1
      loop
        line(frame, y, geometry_c.width);
      end loop;
    end procedure;
  begin
    vsync_s <= '0';
    href_s <= '0';
    bus_data_s <= (others => '-');

    wait until reset_n_s = '1';
    cycles(4);

    -- Tail of a frame whose sync came before reset
    line(0, 1, 4);
    line(0, 2, 4);

    whole_frame(1);

    frame_sync;
    line(2, 0, 4);
    line(2, 1, 2);
    line(2, 2, 6);
    line(2, 3, 4);

    frame_sync;
    line(3, 0, 4);
    line(3, 1, 4);

    frame_sync;
    line(4, 0, 4);
    line(4, 1, 2);

    whole_frame(5);
    whole_frame(6);
    whole_frame(7);

    cycles(50);
    bus_done_s <= true;
    wait;
  end process;

  checker: process is
    variable index, x, overflows, stall: natural;
    variable l: line_t;
    variable last: boolean;
    variable c: rgb24;

    function where(l: line_t; x: natural) return string
    is
    begin
      return "Frame " & to_string(l.frame) & " line " & to_string(l.y)
        & " pixel " & to_string(x);
    end function;
  begin
    done_s <= "0";
    ready_s <= true;
    index := 0;
    x := 0;
    overflows := 0;
    stall := 0;

    wait until reset_n_s = '1';

    while not bus_done_s
    loop
      wait until rising_edge(clock_s);

      if overflow_s = '1' then
        overflows := overflows + 1;
      end if;

      if is_taken(config_c, stream_s.m, stream_s.s) then
        assert index < expected_c'length
          report "Beat after the last expected one"
          severity failure;

        l := expected_c(index);
        last := x = l.length - 1;
        c := to_rgb24(config_c, pixel(config_c, stream_s.m));

        assert is_sof(config_c, stream_s.m) = (l.sof and x = 0)
          report where(l, x) & " disagrees on opening the frame"
          severity failure;
        assert is_last(config_c, stream_s.m) = last
          report where(l, x) & " disagrees on closing the line"
          severity failure;
        assert is_eof(config_c, stream_s.m) = (last and l.eof)
          report where(l, x) & " disagrees on closing the frame"
          severity failure;
        assert is_error(config_c, stream_s.m) = (last and l.error)
          report where(l, x) & " disagrees on the line being in error"
          severity failure;
        assert c = rgb565_color(word(l.frame, l.y, x))
          report where(l, x) & " came out as "
          & to_hex_string(std_ulogic_vector(c.r))
          & to_hex_string(std_ulogic_vector(c.g))
          & to_hex_string(std_ulogic_vector(c.b))
          severity failure;

        if l.frame = stall_frame_c and l.y = stall_y_c and x = 0 then
          stall := stall_cycles_c;
        end if;

        if last then
          index := index + 1;
          x := 0;
        else
          x := x + 1;
        end if;
      end if;

      wait until falling_edge(clock_s);
      ready_s <= stall = 0;
      if stall /= 0 then
        stall := stall - 1;
      end if;
    end loop;

    assert index = expected_c'length
      report "Only " & to_string(index) & " lines out of "
      & to_string(expected_c'length) & " came out"
      severity failure;
    assert overflows = expected_overflows_c
      report to_string(overflows) & " overflows reported, expected "
      & to_string(expected_overflows_c)
      severity failure;

    done_s <= "1";
    wait;
  end process;

end architecture;
