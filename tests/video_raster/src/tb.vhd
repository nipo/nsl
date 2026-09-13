library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_color, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;

entity tb is
end entity;

architecture arch of tb is

  -- Small enough to walk whole frames, and a width that is not a
  -- multiple of the wide beat pixel count.
  constant geometry_c: geometry_t := geometry(7, 3);
  constant config_c: config_t := config(pixels => 1);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal stream_s: bus_t;

  signal gen_x_s: unsigned(x_width(geometry_c)-1 downto 0);
  signal gen_y_s: unsigned(y_width(geometry_c)-1 downto 0);
  signal gen_pixel_s: pixel_vector(0 to 0);

  signal sof_s, sol_s, ready_s, valid_s, synced_s: std_ulogic;
  signal pixel_s: pixel_t;

  -- Raster owner holds sink timing, and can be told to skip a pixel
  -- to shear the stream on purpose.
  signal raster_run_s: std_ulogic;
  signal raster_starve_s: std_ulogic;

  function coordinate_color(x, y: natural) return nsl_color.rgb.rgb24
  is
  begin
    return nsl_color.rgb.rgb24'(r => to_unsigned(x * 16 + y, 8),
                                g => to_unsigned(y, 8),
                                b => to_unsigned(x, 8));
  end function;

begin

  clock: nsl_simulation.driver.simulation_driver
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

  -- A generator answering what colour sits at a coordinate
  gen_pixel_s(0) <= to_pixel(config_c,
                             coordinate_color(to_integer(gen_x_s),
                                              to_integer(gen_y_s)));

  framer: nsl_video.raster.pixel_stream_framer
    generic map(
      geometry_c => geometry_c,
      config_c => config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      x_o => gen_x_s,
      y_o => gen_y_s,
      pixel_i => gen_pixel_s,
      out_o => stream_s.m,
      out_i => stream_s.s
      );

  unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => stream_s.m,
      in_o => stream_s.s,
      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => ready_s,
      valid_o => valid_s,
      pixel_o => pixel_s,
      synced_o => synced_s
      );

  -- A sink raster: states where it opens a frame and a line, then
  -- takes one pixel per cycle whether or not one is on offer.
  raster: process is
    variable x, y: natural;
  begin
    sof_s <= '0';
    sol_s <= '0';
    ready_s <= '0';

    wait until reset_n_s = '1';

    loop
      wait until rising_edge(clock_s) and raster_run_s = '1';

      for y in 0 to geometry_c.height-1
      loop
        if y = 0 then
          sof_s <= '1';
        end if;
        sol_s <= '1';
        wait until rising_edge(clock_s);
        sof_s <= '0';
        sol_s <= '0';

        for x in 0 to geometry_c.width-1
        loop
          if raster_starve_s = '1' and x = 2 and y = 1 then
            ready_s <= '0';
          else
            ready_s <= '1';
          end if;
          wait until rising_edge(clock_s);
        end loop;

        ready_s <= '0';
        -- Blanking
        wait until rising_edge(clock_s);
        wait until rising_edge(clock_s);
      end loop;
    end loop;
  end process;

  main: process is
    variable c: nsl_color.rgb.rgb24;

    -- Walks a whole frame the sink raster asks for, checking every
    -- pixel is the one the generator makes at that coordinate.
    procedure check_frame is
    begin
      wait until rising_edge(clock_s) and sof_s = '1';

      for y in 0 to geometry_c.height-1
      loop
        if y /= 0 then
          wait until rising_edge(clock_s) and sol_s = '1';
        end if;

        for x in 0 to geometry_c.width-1
        loop
          wait until rising_edge(clock_s) and ready_s = '1';

          assert valid_s = '1'
            report "Pixel " & to_string(x) & "," & to_string(y)
            & " is missing"
            severity failure;

          c := to_rgb24(config_c, pixel_s);
          assert c = coordinate_color(x, y)
            report "Pixel " & to_string(x) & "," & to_string(y)
            & " is not what the generator makes there"
            severity failure;
        end loop;
      end loop;
    end procedure;
  begin
    done_s <= "0";
    raster_run_s <= '0';
    raster_starve_s <= '0';

    wait until reset_n_s = '1';

    assert synced_s = '0'
      report "Unframer must not claim sync before a frame went through"
      severity failure;

    -- The sink opens frames on its own timing and the source opens
    -- them on the stream.  Neither waits for the other, and they
    -- still meet.

    raster_run_s <= '1';
    wait until rising_edge(clock_s) and synced_s = '1';

    for frame in 0 to 2
    loop
      check_frame;
      assert synced_s = '1'
        report "Unframer should hold sync through frame " & to_string(frame)
        severity failure;
    end loop;

    -- A pixel the raster does not take leaves the stream a pixel
    -- behind for the rest of the frame, so sync has to drop rather
    -- than let a sheared frame through

    raster_starve_s <= '1';
    wait until rising_edge(clock_s) and sof_s = '1';
    wait until rising_edge(clock_s) and synced_s = '0';
    raster_starve_s <= '0';

    -- and the next whole frame is picked back up

    wait until rising_edge(clock_s) and synced_s = '1';
    check_frame;
    check_frame;

    done_s <= "1";
    wait;
  end process;

end architecture;
