library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_amba, nsl_sitronix, nsl_spi, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_data.text.all;

-- The whole way from a raster off a link to a panel: thinned, carried
-- across to another clock, and handed to something that owns its own
-- scan.
--
-- Everything awkward about that path is here.  The stream starts late,
-- as a link does.  It cannot be held up, as a link cannot.  The panel
-- runs on its own clock and takes pixels more slowly than they arrive,
-- so something has to give -- and what gives has to be whole frames,
-- since a frame short of pixels is one the far end can never follow.
entity tb is
end entity;

architecture arch of tb is

  -- Sized so the panel is comfortably faster than the link feeding
  -- it, as it is on a board: a thumbnail of a big raster arrives
  -- slowly.
  constant in_geometry_c: geometry_t := geometry(128, 72);
  constant out_geometry_c: geometry_t := geometry(8, 6);

  -- What a link hands over cannot be held up; everything after the
  -- thinning can be
  constant link_config_c: config_t := config(pixels => 1, ready => false);
  constant panel_config_c: config_t := config(pixels => 1);

  constant stream_delay_c: natural := 2000;
  constant fifo_depth_c: natural := 64;

  signal link_clock_s, panel_clock_s: std_ulogic;
  signal reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal link_s, small_s, gated_s: nsl_video.pixel_stream.bus_t;
  signal overflow_s: std_ulogic;
  signal fifo_clock_s: std_ulogic_vector(0 to 1);

  signal frame_keep_s, frame_turn_s, passing_s: std_ulogic;


  -- The panel driver as it really is, rather than a model of it: its
  -- scan opens a frame once and then stands at its first pixel, which
  -- is the thing worth being faithful about.
  signal real_s: nsl_video.pixel_stream.bus_t;
  signal real_synced_s: std_ulogic;
  signal real_spi_s: nsl_spi.spi.spi_slave_i;
  signal real_taken_s: natural;
  signal real_dc_s: std_ulogic;
  signal magenta_s, blue_s, black_s, other_s: natural;
  signal sck_d_s: std_ulogic;

  -- The colours that come out wrong on the panel.  Magenta and blue
  -- differ only in red, so one arriving as the other says red was
  -- lost, and black says whether red arrives when it should not.
  function card(x, y: natural) return pixel_t
  is
    variable ret: pixel_t := pixel_zero_c;
  begin
    case (x / 16) mod 3 is
      when 0 =>
        ret(0) := to_unsigned(255, 16);
        ret(2) := to_unsigned(255, 16);
      when 1 =>
        ret(2) := to_unsigned(255, 16);
      when others =>
        null;
    end case;
    return ret;
  end function;

  -- What the driver makes of them: RGB565 by truncation
  constant magenta_565_c: unsigned(15 downto 0) := x"f81f";
  constant blue_565_c: unsigned(15 downto 0) := x"001f";
  constant black_565_c: unsigned(15 downto 0) := x"0000";

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      -- Slower than the link, and not a multiple of it
      clock_period(1) => 27 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => link_clock_s,
      clock_o(1) => panel_clock_s,
      done_i => done_s
      );

  -- A link, silent at first and never willing to wait
  source: process is
  begin
    link_s.m <= transfer_defaults(link_config_c);

    wait until reset_n_s = '1';

    for i in 0 to stream_delay_c-1
    loop
      wait until rising_edge(link_clock_s);
    end loop;

    loop
      for y in 0 to in_geometry_c.height-1
      loop
        for x in 0 to in_geometry_c.width-1
        loop
          link_s.m <= transfer(
            link_config_c,
            card(x, y),
            sof => x = 0 and y = 0,
            last => x = in_geometry_c.width-1,
            eof => x = in_geometry_c.width-1 and y = in_geometry_c.height-1);

          wait until rising_edge(link_clock_s);
        end loop;
      end loop;
    end loop;
  end process;

  thin: nsl_video.raster.pixel_stream_decimator
    generic map(
      in_config_c => link_config_c,
      out_config_c => panel_config_c,
      in_geometry_c => in_geometry_c,
      out_geometry_c => out_geometry_c
      )
    port map(
      clock_i => link_clock_s,
      reset_n_i => reset_n_s,
      in_i => link_s.m,
      in_o => link_s.s,
      out_o => small_s.m,
      out_i => small_s.s,
      overflow_o => overflow_s
      );

  -- A frame at a time to the panel, or none at all
  passing_s <= frame_turn_s when is_sof(panel_config_c, small_s.m)
               else frame_keep_s;

  gated_s.m <= small_s.m when passing_s = '1'
               else transfer_defaults(panel_config_c);
  small_s.s <= gated_s.s when passing_s = '1'
               else accept(panel_config_c, true);

  frame_gate: process(link_clock_s, reset_n_s) is
  begin
    if rising_edge(link_clock_s) then
      if is_taken(panel_config_c, small_s.m, small_s.s) then
        if is_sof(panel_config_c, small_s.m) then
          frame_keep_s <= frame_turn_s;
        end if;
        if is_last(panel_config_c, small_s.m)
          and is_eof(panel_config_c, small_s.m) then
          frame_turn_s <= not frame_turn_s;
        end if;
      end if;
    end if;

    if reset_n_s = '0' then
      frame_keep_s <= '0';
      frame_turn_s <= '1';
    end if;
  end process;

  fifo_clock_s(0) <= link_clock_s;
  fifo_clock_s(1) <= panel_clock_s;

  real_panel: nsl_sitronix.st7735.st7735_spi_driver
    generic map(
      -- Told a slow clock so its power-up waits, which are a tenth of
      -- a second of real time, pass in a simulation
      clock_i_hz_c => 100_000,
      config_c => panel_config_c,
      spi_hz_c => 50_000,
      geometry_c => out_geometry_c
      )
    port map(
      clock_i => panel_clock_s,
      reset_n_i => reset_n_s,

      spi_o => real_spi_s,
      dc_o => real_dc_s,
      reset_n_o => open,

      pixel_i => real_s.m,
      pixel_o => real_s.s,

      synced_o => real_synced_s
      );

  real_count: process(panel_clock_s, reset_n_s) is
  begin
    if rising_edge(panel_clock_s) then
      if is_taken(panel_config_c, real_s.m, real_s.s) then
        real_taken_s <= real_taken_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      real_taken_s <= 0;
    end if;
  end process;

  real_cross: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => as_stream_config(panel_config_c),
      depth_c => fifo_depth_c,
      clock_count_c => 2
      )
    port map(
      clock_i => fifo_clock_s,
      reset_n_i => reset_n_s,
      in_i => gated_s.m,
      in_o => gated_s.s,
      in_free_o => open,
      out_o => real_s.m,
      out_i => real_s.s,
      out_available_o => open
      );

  -- What the driver is actually being handed: how long its lines are,
  -- and whether it keeps losing the frame it found.
  watch: process is
    variable in_line, bad_lines, lines, sync_rises, sync_falls: natural := 0;
    variable was_synced: std_ulogic := '0';
  begin
    loop
      wait until rising_edge(panel_clock_s);

      if real_synced_s = '1' and was_synced = '0' then
        sync_rises := sync_rises + 1;
        report "DBG sync up at " & time'image(now)
          & " after " & to_string(real_taken_s) & " pixels" severity note;
      end if;
      if real_synced_s = '0' and was_synced = '1' then
        sync_falls := sync_falls + 1;
        report "DBG sync LOST at " & time'image(now)
          & " after " & to_string(real_taken_s) & " pixels, "
          & to_string(in_line) & " into a line" severity note;
      end if;
      was_synced := real_synced_s;

      if is_taken(panel_config_c, real_s.m, real_s.s) then
        if lines < 12 then
          report "DBG beat x=" & to_string(to_integer(pixel(panel_config_c, real_s.m)(0)))
            & " y=" & to_string(to_integer(pixel(panel_config_c, real_s.m)(1)))
            & " sof=" & boolean'image(is_sof(panel_config_c, real_s.m))
            & " last=" & boolean'image(is_last(panel_config_c, real_s.m))
            & " eof=" & boolean'image(is_eof(panel_config_c, real_s.m))
            & " synced=" & std_ulogic'image(real_synced_s)
            severity note;
        end if;
        in_line := in_line + 1;
        if is_last(panel_config_c, real_s.m) then
          lines := lines + 1;
          if in_line /= out_geometry_c.width then
            bad_lines := bad_lines + 1;
            report "DBG line " & to_string(lines) & " was " & to_string(in_line)
              & " beats, not " & to_string(out_geometry_c.width) severity note;
          end if;
          in_line := 0;
        end if;
      end if;
    end loop;
  end process;

  -- What actually reaches the panel: the words the driver shifts out
  -- with dc high are the last word on the subject of what colour a
  -- pixel ended up.  Which pixel is which does not matter here -- what
  -- matters is that all three colours arrive and nothing else does.
  -- Sampled off the panel clock rather than off the serial clock:
  -- when the driver has no pixel it stops clocking altogether, and a
  -- process waiting on that clock would never wake to notice sync had
  -- gone.
  spi_watch: process(panel_clock_s, reset_n_s) is
    variable word: unsigned(15 downto 0);
    variable bits: natural range 0 to 16;
  begin
    if rising_edge(panel_clock_s) then
      -- A run that lost sync was being handed truncated frames, and
      -- what it shifted out says nothing about colour.  Only a run
      -- that holds counts.
      if real_synced_s = '0' then
        magenta_s <= 0;
        blue_s <= 0;
        black_s <= 0;
        other_s <= 0;
        bits := 0;
      elsif real_spi_s.sck = '1' and sck_d_s = '0' and real_dc_s = '1' then
        word := word(14 downto 0) & real_spi_s.mosi;

        if bits = 15 then
          bits := 0;

          if word = magenta_565_c then
            magenta_s <= magenta_s + 1;
          elsif word = blue_565_c then
            blue_s <= blue_s + 1;
          elsif word = black_565_c then
            black_s <= black_s + 1;
          else
            other_s <= other_s + 1;
            report "DBG panel got " & to_hex_string(std_ulogic_vector(word))
              & ", which is none of the three sent" severity note;
          end if;
        else
          bits := bits + 1;
        end if;
      end if;

      sck_d_s <= real_spi_s.sck;
    end if;

    if reset_n_s = '0' then
      magenta_s <= 0;
      blue_s <= 0;
      black_s <= 0;
      other_s <= 0;
      sck_d_s <= '0';
    end if;
  end process;

  main: process is
    variable waited: natural := 0;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    while waited < 4000000
    loop
      wait until rising_edge(panel_clock_s);
      waited := waited + 1;
      exit when real_taken_s >= out_geometry_c.width * out_geometry_c.height * 2;
    end loop;

    report "DBG synced=" & std_ulogic'image(real_synced_s)
      & " taken=" & to_string(real_taken_s)
      & " overflow=" & std_ulogic'image(overflow_s)
      severity note;

    report "DBG magenta=" & to_string(magenta_s) & " blue=" & to_string(blue_s)
      & " black=" & to_string(black_s) & " other=" & to_string(other_s)
      severity note;

    assert real_synced_s = '1'
      report "The panel driver never found a frame in what the link sent"
      severity failure;

    -- Red has to survive: magenta and blue differ in nothing else
    assert magenta_s /= 0
      report "The panel was sent magenta and never received any, so red is "
      & "being lost between the link and the panel"
      severity failure;
    assert blue_s /= 0 and black_s /= 0
      report "The panel did not receive the other two colours either"
      severity failure;
    assert other_s = 0
      report to_string(other_s) & " words reached the panel that are none of "
      & "the three colours sent"
      severity failure;
    assert real_taken_s >= out_geometry_c.width * out_geometry_c.height * 2
      report "The panel took " & to_string(real_taken_s)
      & " pixels, which is short of two frames"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
