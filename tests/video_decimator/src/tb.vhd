library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_amba, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_data.text.all;

-- Makes a smaller raster out of a bigger one and counts what came out.
--
-- What matters is not which pixels survive but how many: a line has to
-- hold exactly the output width whatever the ratio, and a frame
-- exactly the output height.  A ratio that divides and one that does
-- not are both tried, since the second is where a count drifts.
--
-- Each pixel carries where it came from, so where a line and a frame
-- end can be held against where they ended going in.
entity tb is
end entity;

architecture arch of tb is

  constant config_c: config_t := config(pixels => 1, components => 3,
                                        component_bits => 8);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  -- A ratio that divides, and one that does not
  constant exact_in_c: geometry_t := (width => 32, height => 18);
  constant exact_out_c: geometry_t := (width => 8, height => 6);
  constant odd_in_c: geometry_t := (width => 20, height => 9);
  constant odd_out_c: geometry_t := (width => 8, height => 6);

  type link_t is
  record
    in_m: master_t;
    in_s: slave_t;
    out_m: master_t;
    out_s: slave_t;
    overflow: std_ulogic;
  end record;

  signal exact_s, odd_s: link_t;

  signal exact_done_s, odd_done_s: boolean := false;

  -- Where a pixel came from, and something in every bit of every
  -- component: a component quietly swapped for another, or shifted
  -- inside its byte, has to show.  Colour bars cannot say that, their
  -- components being all zeros or all ones.
  function pixel_of(x, y: natural) return pixel_t
  is
    variable ret: pixel_t := pixel_zero_c;
  begin
    ret(0) := to_unsigned((x * 7 + y) mod 256, ret(0)'length);
    ret(1) := to_unsigned((y * 13 + x * 3 + 16#5a#) mod 256, ret(1)'length);
    ret(2) := to_unsigned((x * 29 + y * 11 + 16#a5#) mod 256, ret(2)'length);
    return ret;
  end function;

  -- Which pixels should survive, worked out here rather than taken on
  -- trust: the accumulator is walked again from the outside, so the
  -- test knows the coordinate of every beat it should be handed and
  -- can hold the pixel against it.
  procedure walk(signal m: in master_t;
                 signal s: in slave_t;
                 constant in_geometry: geometry_t;
                 constant out_geometry: geometry_t;
                 constant msg: string;
                 signal flag: out boolean) is
    constant h_threshold: natural := in_geometry.width - out_geometry.width;
    constant v_threshold: natural := in_geometry.height - out_geometry.height;
    variable v_acc, h_acc: natural;
    variable p: pixel_t;
    variable in_line, lines: natural;

    procedure take is
    begin
      wait until rising_edge(clock_s) and is_taken(config_c, m, s);
      p := pixel(config_c, m);
    end procedure;
  begin
    -- Start at a frame the decimator opened
    loop
      wait until rising_edge(clock_s) and is_taken(config_c, m, s);
      exit when is_sof(config_c, m);
    end loop;
    p := pixel(config_c, m);

    v_acc := 0;
    lines := 0;

    for y in 0 to in_geometry.height-1
    loop
      if v_acc >= v_threshold then
        -- A kept line: every pixel of it has to arrive, in order
        v_acc := v_acc - v_threshold;
        h_acc := 0;
        in_line := 0;

        for x in 0 to in_geometry.width-1
        loop
          if h_acc >= h_threshold then
            h_acc := h_acc - h_threshold;

            for c in 0 to config_c.component_count-1
            loop
              assert p(c) = pixel_of(x, y)(c)
                report msg & ": pixel " & to_string(x) & "," & to_string(y)
                & " component " & to_string(c) & " came back as "
                & to_hex_string(std_ulogic_vector(p(c)))
                & ", not " & to_hex_string(std_ulogic_vector(pixel_of(x, y)(c)))
                severity failure;
            end loop;

            in_line := in_line + 1;

            assert is_last(config_c, m) = (x = in_geometry.width-1)
              report msg & ": pixel " & to_string(x) & "," & to_string(y)
              & " disagrees on closing the line"
              severity failure;
            assert is_eof(config_c, m) = (x = in_geometry.width-1
                                          and y = in_geometry.height-1)
              report msg & ": pixel " & to_string(x) & "," & to_string(y)
              & " disagrees on closing the frame"
              severity failure;

            exit when x = in_geometry.width-1
              and y = in_geometry.height-1;
            take;
          else
            h_acc := h_acc + out_geometry.width;
          end if;
        end loop;

        assert in_line = out_geometry.width
          report msg & ": line " & to_string(y) & " held "
          & to_string(in_line) & " pixels, not "
          & to_string(out_geometry.width)
          severity failure;

        lines := lines + 1;
      else
        v_acc := v_acc + out_geometry.height;
      end if;
    end loop;

    assert lines = out_geometry.height
      report msg & ": a frame held " & to_string(lines) & " lines, not "
      & to_string(out_geometry.height)
      severity failure;

    flag <= true;
  end procedure;

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

  exact: nsl_video.raster.pixel_stream_decimator
    generic map(
      in_config_c => config_c,
      out_config_c => config_c,
      in_geometry_c => exact_in_c,
      out_geometry_c => exact_out_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => exact_s.in_m,
      in_o => exact_s.in_s,
      out_o => exact_s.out_m,
      out_i => exact_s.out_s,
      overflow_o => exact_s.overflow
      );

  exact_s.out_s <= accept(config_c, true);

  odd: nsl_video.raster.pixel_stream_decimator
    generic map(
      in_config_c => config_c,
      out_config_c => config_c,
      in_geometry_c => odd_in_c,
      out_geometry_c => odd_out_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => odd_s.in_m,
      in_o => odd_s.in_s,
      out_o => odd_s.out_m,
      out_i => odd_s.out_s,
      overflow_o => odd_s.overflow
      );

  odd_s.out_s <= accept(config_c, true);

  exact_source: process is
  begin
    exact_s.in_m <= transfer_defaults(config_c);
    wait until reset_n_s = '1';

    for frame in 0 to 5
    loop
      for y in 0 to exact_in_c.height-1
      loop
        for x in 0 to exact_in_c.width-1
        loop
          exact_s.in_m <= transfer(
            config_c, pixel_of(x, y),
            sof => x = 0 and y = 0,
            last => x = exact_in_c.width-1,
            eof => x = exact_in_c.width-1 and y = exact_in_c.height-1);
          wait until rising_edge(clock_s);
        end loop;
      end loop;
    end loop;

    exact_s.in_m <= transfer_defaults(config_c);
    wait;
  end process;

  odd_source: process is
  begin
    odd_s.in_m <= transfer_defaults(config_c);
    wait until reset_n_s = '1';

    for frame in 0 to 5
    loop
      for y in 0 to odd_in_c.height-1
      loop
        for x in 0 to odd_in_c.width-1
        loop
          odd_s.in_m <= transfer(
            config_c, pixel_of(x, y),
            sof => x = 0 and y = 0,
            last => x = odd_in_c.width-1,
            eof => x = odd_in_c.width-1 and y = odd_in_c.height-1);
          wait until rising_edge(clock_s);
        end loop;
      end loop;
    end loop;

    odd_s.in_m <= transfer_defaults(config_c);
    wait;
  end process;

  -- One frame of each, counted.  Both run at once, since both links
  -- are running at once.
  check_exact: process is
  begin
    walk(exact_s.out_m, exact_s.out_s, exact_in_c, exact_out_c,
         "32x18 to 8x6", exact_done_s);
    wait;
  end process;

  check_odd: process is
  begin
    walk(odd_s.out_m, odd_s.out_s, odd_in_c, odd_out_c,
         "20x9 to 8x6", odd_done_s);
    wait;
  end process;

  main: process is
  begin
    done_s <= "0";
    wait until reset_n_s = '1';
    wait until exact_done_s and odd_done_s;

    assert exact_s.overflow = '0' and odd_s.overflow = '0'
      report "A pixel was dropped with nothing holding the stream up"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
