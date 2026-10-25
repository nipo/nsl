library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_video, nsl_simulation;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  constant address_width_c : positive := 16;
  constant base_c : unsigned(15 downto 0) := x"1000";
  constant buffer_size_c : unsigned(15 downto 0) := x"0400";

  signal clock_s, reset_n_s, dut_reset_n_s, soft_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal writer_base_s, reader_base_s : unsigned(address_width_c-1 downto 0);
  signal writer_done_s, display_request_s, reader_start_s, reader_ready_s : std_ulogic;
  signal writer_status_s : nsl_video.vdma.frame_status_t;
  signal dropped_s, repeated_s, skipped_s : std_ulogic;

begin

  dut_reset_n_s <= reset_n_s and soft_reset_n_s;

  dut: nsl_video.vdma.vdma_triple_buffer
    generic map(
      address_width_c => address_width_c,
      base_c => base_c,
      buffer_size_c => buffer_size_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => dut_reset_n_s,

      writer_base_o => writer_base_s,
      writer_done_i => writer_done_s,
      writer_status_i => writer_status_s,

      display_request_i => display_request_s,
      reader_base_o => reader_base_s,
      reader_start_o => reader_start_s,
      reader_ready_i => reader_ready_s,

      frame_dropped_o => dropped_s,
      frame_repeated_o => repeated_s,
      frame_skipped_o => skipped_s
      );

  -- Writer, reader and display request generator are modelled at the
  -- handshake level. Writer samples its base one cycle after done at
  -- the earliest, as vdma_writer does in its SYNC state.
  model: process
    type scenario_t is
    record
      name: string(1 to 12);
      write_min, write_max: natural;
      gap_max: natural;
      read_min, read_max: natural;
      request_min, request_max: natural;
      incomplete_percent: natural;
      cycles: natural;
    end record;
    type scenario_vector is array(natural range <>) of scenario_t;

    constant scenarios_c : scenario_vector := (
      ("fast writer ", 40, 60, 5, 80, 100, 140, 160, 0, 30000),
      ("slow writer ", 180, 220, 20, 50, 60, 70, 90, 0, 30000),
      ("same rate   ", 60, 140, 10, 70, 90, 60, 140, 0, 30000),
      ("incomplete  ", 30, 150, 10, 40, 80, 50, 150, 40, 30000),
      ("busy request", 30, 50, 0, 100, 120, 1, 20, 10, 30000),
      ("tight       ", 1, 3, 0, 1, 3, 1, 3, 20, 30000)
      );

    type int_vector is array(0 to 2) of integer;
    type bool_vector is array(0 to 2) of boolean;

    variable seed1, seed2 : positive := 1;

    impure function rand(lo, hi: natural) return natural is
      variable x: real;
    begin
      uniform(seed1, seed2, x);
      return lo + integer(floor(x * real(hi - lo + 1)));
    end function;

    impure function chance(p: real) return boolean is
      variable x: real;
    begin
      uniform(seed1, seed2, x);
      return x < p;
    end function;

    function index(a: unsigned) return integer is
      variable off: unsigned(a'length-1 downto 0);
    begin
      off := a - base_c;
      assert off(9 downto 0) = 0 and off < buffer_size_c * 3
        report "Base out of buffer set" severity failure;
      return to_integer(off / buffer_size_c);
    end function;

    type wstate_t is (W_GAP, W_BUSY, W_DONE);
    variable wstate: wstate_t;
    variable wcount, widx, wframe: integer;
    variable wcomplete: boolean;

    variable rbusy: boolean;
    variable rcount, ridx: integer;
    variable qcount: integer;

    -- Frame number held by each buffer, -1 for none/garbage.
    variable content: int_vector;
    variable being_written: bool_vector;

    variable newest, newest_d1, newest_d2: integer;
    variable last_shown: integer;

    variable n_complete, n_incomplete, n_shown, n_repeat_seen,
      n_dropped, n_repeated, n_skipped, n_starts: natural;
    variable pending: integer;
    variable s: scenario_t;
  begin
    done_s <= "0";
    soft_reset_n_s <= '0';
    writer_done_s <= '0';
    writer_status_s <= (complete => '0', truncated => '0', line_error => '0',
                        overflow => '0', bus_error => '0');
    display_request_s <= '0';
    reader_ready_s <= '1';

    wait until reset_n_s = '1';

    for sc in scenarios_c'range
    loop
      s := scenarios_c(sc);
      log_info("Scenario " & s.name);

      soft_reset_n_s <= '0';
      writer_done_s <= '0';
      display_request_s <= '0';
      reader_ready_s <= '1';
      wait until rising_edge(clock_s);
      wait until rising_edge(clock_s);
      soft_reset_n_s <= '1';

      wstate := W_GAP;
      wcount := rand(0, s.gap_max);
      wframe := 0;
      rbusy := false;
      qcount := rand(s.request_min, s.request_max);
      content := (others => -1);
      being_written := (others => false);
      newest := -1;
      newest_d1 := -1;
      newest_d2 := -1;
      last_shown := -1;
      n_complete := 0;
      n_incomplete := 0;
      n_shown := 0;
      n_repeat_seen := 0;
      n_dropped := 0;
      n_repeated := 0;
      n_skipped := 0;
      n_starts := 0;

      for cycle in 0 to s.cycles + 2000
      loop
        wait until rising_edge(clock_s);

        newest_d2 := newest_d1;
        newest_d1 := newest;

        -- Invariants on DUT outputs.
        assert writer_base_s /= reader_base_s
          report "Writer and reader bases are the same" severity failure;
        if rbusy then
          assert index(writer_base_s) /= ridx
            report "Writer base points to buffer being read" severity failure;
          assert not being_written(ridx)
            report "Buffer being read is being written" severity failure;
        end if;

        if dropped_s = '1' then
          n_dropped := n_dropped + 1;
        end if;
        if repeated_s = '1' then
          n_repeated := n_repeated + 1;
        end if;
        if skipped_s = '1' then
          n_skipped := n_skipped + 1;
        end if;

        -- Writer
        writer_done_s <= '0';
        case wstate is
          when W_GAP =>
            if cycle >= s.cycles then
              null;
            elsif wcount /= 0 then
              wcount := wcount - 1;
            else
              widx := index(writer_base_s);
              assert not (rbusy and widx = ridx)
                report "Writer starts on buffer being read" severity failure;
              being_written(widx) := true;
              content(widx) := -1;
              wcomplete := not chance(real(s.incomplete_percent) / 100.0);
              wcount := rand(s.write_min, s.write_max);
              wstate := W_BUSY;
            end if;

          when W_BUSY =>
            if wcount /= 0 then
              wcount := wcount - 1;
            else
              being_written(widx) := false;
              writer_done_s <= '1';
              if wcomplete then
                writer_status_s.complete <= '1';
                writer_status_s.overflow <= '0';
                content(widx) := wframe;
                newest := wframe;
                n_complete := n_complete + 1;
              else
                writer_status_s.complete <= '0';
                writer_status_s.overflow <= '1';
                n_incomplete := n_incomplete + 1;
              end if;
              wframe := wframe + 1;
              wstate := W_DONE;
            end if;

          when W_DONE =>
            wcount := rand(0, s.gap_max);
            wstate := W_GAP;
        end case;

        -- Reader
        if rbusy then
          assert reader_start_s = '0'
            report "Reader started while busy" severity failure;
          if rcount /= 0 then
            rcount := rcount - 1;
          else
            rbusy := false;
            reader_ready_s <= '1';
          end if;
        elsif reader_start_s = '1' then
          ridx := index(reader_base_s);
          n_starts := n_starts + 1;
          assert not being_written(ridx)
            report "Reader starts on buffer being written" severity failure;
          if newest_d2 < 0 then
            assert ridx = 0
              report "Reader not on buffer 0 before first frame" severity failure;
            n_repeat_seen := n_repeat_seen + 1;
          else
            assert content(ridx) >= 0
              report "Reader starts on incomplete buffer" severity failure;
            assert content(ridx) >= newest_d2
              report "Reader does not display newest frame" severity failure;
            assert content(ridx) >= last_shown
              report "Frame order not monotonic" severity failure;
            if content(ridx) = last_shown then
              n_repeat_seen := n_repeat_seen + 1;
            else
              n_shown := n_shown + 1;
            end if;
            last_shown := content(ridx);
          end if;
          rbusy := true;
          rcount := rand(s.read_min, s.read_max);
          reader_ready_s <= '0';
        end if;

        -- Display requests
        display_request_s <= '0';
        if qcount /= 0 then
          qcount := qcount - 1;
        else
          display_request_s <= '1';
          qcount := rand(s.request_min, s.request_max);
        end if;
      end loop;

      pending := n_complete - n_shown - n_skipped;
      log_info("  complete " & integer'image(n_complete)
               & ", incomplete " & integer'image(n_incomplete)
               & ", starts " & integer'image(n_starts)
               & ", shown " & integer'image(n_shown)
               & ", repeated " & integer'image(n_repeated)
               & ", skipped " & integer'image(n_skipped));

      assert n_complete > 20 and n_starts > 20
        report "Scenario did not run" severity failure;
      assert n_dropped = n_incomplete
        report "Dropped count mismatch" severity failure;
      assert n_repeated = n_repeat_seen
        report "Repeated count mismatch" severity failure;
      assert pending = 0 or pending = 1
        report "Complete frames unaccounted for" severity failure;
      if s.incomplete_percent = 0 and s.write_min > s.request_max + s.read_max then
        assert n_skipped = 0
          report "Frames skipped with a slow writer" severity failure;
      end if;
    end loop;

    log_info("All scenarios passed");
    done_s <= "1";
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 32 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
