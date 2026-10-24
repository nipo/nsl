library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_data, nsl_simulation;
use nsl_video.pixel_stream.all;
use nsl_data.text.all;

-- Feeds RGB565 beats through rgb565_unpacker with valid and ready
-- going on and off independently, and checks every beat comes out
-- once, in order, with its framing and its components widened by
-- bit replication.
entity tb is
end entity;

architecture arch of tb is

  constant in_config_c: config_t := config(pixels => 1, component_bits => 16,
                                           colorspace => COLORSPACE_RGB565);
  constant out_config_c: config_t := config(pixels => 1, component_bits => 8,
                                            colorspace => COLORSPACE_RGB);
  constant beat_count_c: natural := 600;
  constant line_length_c: natural := 7;
  constant frame_lines_c: natural := 3;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal in_s, out_s: bus_t;
  signal in_valid_s, out_ready_s: boolean;

  function word(index: natural) return unsigned
  is
  begin
    if index = 0 then
      return x"ffff";
    elsif index = 1 then
      return x"0000";
    end if;
    return to_unsigned((index * 40503 + 12345) mod 65536, 16);
  end function;

  function is_line_end(index: natural) return boolean
  is
  begin
    return index mod line_length_c = line_length_c - 1;
  end function;

  function is_frame_start(index: natural) return boolean
  is
  begin
    return index mod (line_length_c * frame_lines_c) = 0;
  end function;

  function is_frame_end(index: natural) return boolean
  is
  begin
    return index mod (line_length_c * frame_lines_c) = line_length_c * frame_lines_c - 1;
  end function;

  function is_bad(index: natural) return boolean
  is
  begin
    return is_line_end(index) and index mod 5 = 1;
  end function;

  function beat(index: natural; valid: boolean) return master_t
  is
    variable p: pixel_t := pixel_zero_c;
  begin
    p(0) := word(index);
    return transfer(cfg => in_config_c,
                    pixel => p,
                    valid => valid,
                    sof => is_frame_start(index),
                    last => is_line_end(index),
                    eof => is_frame_end(index),
                    error => is_bad(index));
  end function;

  -- Pseudo-random on/off pattern
  function toggle(seed, cycle: natural) return boolean
  is
  begin
    return ((cycle * 37 + (cycle / 5) * 11 + seed) mod 13) < 7;
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

  dut: nsl_video.colorspace.rgb565_unpacker
    generic map(
      in_config_c => in_config_c,
      out_config_c => out_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => in_s.m,
      in_o => in_s.s,

      out_o => out_s.m,
      out_i => out_s.s
      );

  source: process is
    variable index, cycle: natural;
  begin
    in_s.m <= beat(0, false);
    index := 0;
    cycle := 0;

    wait until reset_n_s = '1';

    while index < beat_count_c
    loop
      wait until falling_edge(clock_s);
      cycle := cycle + 1;
      -- Full rate for the first frames, then with gaps
      in_s.m <= beat(index, index < 60 or toggle(3, cycle mod 4096));
      wait until rising_edge(clock_s);
      if is_taken(in_config_c, in_s.m, in_s.s) then
        index := index + 1;
      end if;
    end loop;

    wait until falling_edge(clock_s);
    in_s.m <= beat(0, false);
    wait;
  end process;

  out_s.s <= accept(out_config_c, ready => out_ready_s);

  sink: process is
    variable index, cycle: natural;
    variable w: unsigned(15 downto 0);
    variable p: pixel_t;
    variable expected: pixel_t;
  begin
    done_s <= "0";
    out_ready_s <= true;
    index := 0;
    cycle := 0;

    wait until reset_n_s = '1';

    while index < beat_count_c
    loop
      wait until rising_edge(clock_s);
      cycle := cycle + 1;

      if is_taken(out_config_c, out_s.m, out_s.s) then
        w := word(index);
        expected := pixel_zero_c;
        expected(0)(7 downto 0) := w(15 downto 11) & w(15 downto 13);
        expected(1)(7 downto 0) := w(10 downto 5) & w(10 downto 9);
        expected(2)(7 downto 0) := w(4 downto 0) & w(4 downto 2);
        p := pixel(out_config_c, out_s.m);

        for c in 0 to 2
        loop
          assert p(c) = expected(c)
            report "Beat " & to_string(index) & " component " & to_string(c)
            & " is " & to_hex_string(std_ulogic_vector(p(c)))
            & ", expected " & to_hex_string(std_ulogic_vector(expected(c)))
            severity failure;
        end loop;

        assert is_sof(out_config_c, out_s.m) = is_frame_start(index)
          and is_last(out_config_c, out_s.m) = is_line_end(index)
          and is_eof(out_config_c, out_s.m) = is_frame_end(index)
          and is_error(out_config_c, out_s.m) = is_bad(index)
          report "Beat " & to_string(index) & " has wrong framing"
          severity failure;

        index := index + 1;
      end if;

      wait until falling_edge(clock_s);
      -- Always ready for the first frames, then stalling
      out_ready_s <= index < 40 or toggle(5, (cycle * 3) mod 4096);
    end loop;

    for i in 0 to 20
    loop
      wait until rising_edge(clock_s);
      assert not is_valid(out_config_c, out_s.m)
        report "Beat after the last one"
        severity failure;
    end loop;

    done_s <= "1";
    wait;
  end process;

end architecture;
