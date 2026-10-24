library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_amba, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_data.text.all;

-- Widens a raster by pixel repetition and checks every beat that
-- comes out: the pixel it carries, and where it says a frame opens,
-- a line closes, a frame closes and a line is in error.
--
-- Both sides stall at uneven intervals, so a copy count kept across a
-- stall or a beat taken while copies are still owed has to show.  A
-- factor of one is tried as well, it is the case where a beat is
-- taken back to back.
entity tb is
end entity;

architecture arch of tb is

  constant config_c: config_t := config(pixels => 1, components => 3,
                                        component_bits => 8);

  constant geometry_c: geometry_t := (width => 5, height => 3);
  constant frame_count_c: natural := 3;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  type link_t is
  record
    in_m: master_t;
    in_s: slave_t;
    out_m: master_t;
    out_s: slave_t;
  end record;

  type link_vector is array (natural range <>) of link_t;
  type factor_vector is array (natural range <>) of positive;

  constant factor_c: factor_vector(0 to 1) := (3, 1);

  signal link_s: link_vector(0 to 1);

  function pixel_of(frame, x, y: natural) return pixel_t
  is
    variable ret: pixel_t := pixel_zero_c;
  begin
    ret(0) := to_unsigned((x * 7 + y + frame * 3) mod 256, ret(0)'length);
    ret(1) := to_unsigned((y * 13 + x * 3 + 16#5a#) mod 256, ret(1)'length);
    ret(2) := to_unsigned((x * 29 + y * 11 + frame + 16#a5#) mod 256, ret(2)'length);
    return ret;
  end function;

  -- Line 1 of every frame is flagged in error.
  function error_of(y: natural) return boolean
  is
  begin
    return y = 1;
  end function;

  -- Stall pattern: a 16-bit LFSR, one bit a cycle.
  function lfsr_next(s: unsigned(15 downto 0)) return unsigned
  is
  begin
    return s(14 downto 0) & (s(15) xor s(13) xor s(12) xor s(10));
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

  links: for i in link_s'range
  generate
    dut: nsl_video.raster.pixel_stream_repeater
      generic map(
        config_c => config_c,
        factor_c => factor_c(i)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        in_i => link_s(i).in_m,
        in_o => link_s(i).in_s,
        out_o => link_s(i).out_m,
        out_i => link_s(i).out_s
        );

    source: process is
      variable lfsr: unsigned(15 downto 0) := x"ace1";
    begin
      link_s(i).in_m <= transfer_defaults(config_c);
      wait until reset_n_s = '1';

      for frame in 0 to frame_count_c-1
      loop
        for y in 0 to geometry_c.height-1
        loop
          for x in 0 to geometry_c.width-1
          loop
            loop
              wait until falling_edge(clock_s);
              lfsr := lfsr_next(lfsr);
              exit when lfsr(0) = '1';
              link_s(i).in_m <= transfer_defaults(config_c);
            end loop;

            link_s(i).in_m <= transfer(
              config_c, pixel_of(frame, x, y),
              sof => x = 0 and y = 0,
              last => x = geometry_c.width-1,
              eof => x = geometry_c.width-1 and y = geometry_c.height-1,
              error => x = geometry_c.width-1 and error_of(y));

            wait until rising_edge(clock_s) and is_ready(config_c, link_s(i).in_s);
          end loop;
        end loop;
      end loop;

      wait until falling_edge(clock_s);
      link_s(i).in_m <= transfer_defaults(config_c);
      wait;
    end process;

    sink: process is
      variable lfsr: unsigned(15 downto 0) := x"1d2b";
      variable p: pixel_t;
      variable closing: boolean;
      constant ctx: string := "x" & to_string(factor_c(i));
    begin
      done_s(i) <= '0';
      link_s(i).out_s <= accept(config_c, false);
      wait until reset_n_s = '1';

      for frame in 0 to frame_count_c-1
      loop
        for y in 0 to geometry_c.height-1
        loop
          for x in 0 to geometry_c.width-1
          loop
            for c in 0 to factor_c(i)-1
            loop
              loop
                wait until falling_edge(clock_s);
                lfsr := lfsr_next(lfsr);
                link_s(i).out_s <= accept(config_c, lfsr(0) = '1' or lfsr(1) = '1');
                wait until rising_edge(clock_s);
                exit when is_taken(config_c, link_s(i).out_m, link_s(i).out_s);
              end loop;

              p := pixel(config_c, link_s(i).out_m);
              closing := c = factor_c(i)-1;

              for k in 0 to config_c.component_count-1
              loop
                assert p(k) = pixel_of(frame, x, y)(k)
                  report ctx & ": frame " & to_string(frame)
                  & " pixel " & to_string(x) & "," & to_string(y)
                  & " copy " & to_string(c)
                  & " component " & to_string(k) & " came back as "
                  & to_hex_string(std_ulogic_vector(p(k)))
                  severity failure;
              end loop;

              assert is_sof(config_c, link_s(i).out_m)
                = (x = 0 and y = 0 and c = 0)
                report ctx & ": frame " & to_string(frame)
                & " pixel " & to_string(x) & "," & to_string(y)
                & " copy " & to_string(c) & " disagrees on opening the frame"
                severity failure;

              assert is_last(config_c, link_s(i).out_m)
                = (closing and x = geometry_c.width-1)
                report ctx & ": frame " & to_string(frame)
                & " pixel " & to_string(x) & "," & to_string(y)
                & " copy " & to_string(c) & " disagrees on closing the line"
                severity failure;

              if is_last(config_c, link_s(i).out_m) then
                assert is_eof(config_c, link_s(i).out_m)
                  = (y = geometry_c.height-1)
                  report ctx & ": frame " & to_string(frame)
                  & " line " & to_string(y) & " disagrees on closing the frame"
                  severity failure;

                assert is_error(config_c, link_s(i).out_m) = error_of(y)
                  report ctx & ": frame " & to_string(frame)
                  & " line " & to_string(y) & " disagrees on being in error"
                  severity failure;
              end if;
            end loop;
          end loop;
        end loop;
      end loop;

      -- Nothing more may come out once the source is drained.
      wait until falling_edge(clock_s);
      link_s(i).out_s <= accept(config_c, true);
      for k in 0 to 20
      loop
        wait until rising_edge(clock_s);
        assert not is_valid(config_c, link_s(i).out_m)
          report ctx & ": a beat came out past the last copy"
          severity failure;
      end loop;

      done_s(i) <= '1';
      wait;
    end process;
  end generate;

end architecture;
