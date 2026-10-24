library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_amba;
use nsl_amba.axi4_mm.all;

-- Inserts random stalls on every channel of an AXI4-MM link. A
-- stalled channel has both its valid and ready forced low, as if the
-- channel did not see the clock edge.
entity mm_staller is
  generic(
    config_c : nsl_amba.axi4_mm.config_t;
    seed_c : positive;
    pass_permille_c : natural
    );
  port(
    clock_i : in std_ulogic;

    in_i : in nsl_amba.axi4_mm.master_t;
    in_o : out nsl_amba.axi4_mm.slave_t;

    out_o : out nsl_amba.axi4_mm.master_t;
    out_i : in nsl_amba.axi4_mm.slave_t
    );
end entity;

architecture beh of mm_staller is

  signal pass_s : std_ulogic_vector(0 to 4) := (others => '0');

begin

  rand: process(clock_i) is
    variable s1 : positive := seed_c;
    variable s2 : positive := seed_c * 7 + 3;
    variable x : real;
  begin
    if rising_edge(clock_i) then
      for i in pass_s'range
      loop
        uniform(s1, s2, x);
        if x * 1000.0 < real(pass_permille_c) then
          pass_s(i) <= '1';
        else
          pass_s(i) <= '0';
        end if;
      end loop;
    end if;
  end process;

  gate: process(in_i, out_i, pass_s) is
  begin
    out_o <= in_i;
    in_o <= out_i;

    out_o.aw.valid <= in_i.aw.valid and pass_s(0);
    in_o.aw.ready <= out_i.aw.ready and pass_s(0);
    out_o.w.valid <= in_i.w.valid and pass_s(1);
    in_o.w.ready <= out_i.w.ready and pass_s(1);
    in_o.b.valid <= out_i.b.valid and pass_s(2);
    out_o.b.ready <= in_i.b.ready and pass_s(2);
    out_o.ar.valid <= in_i.ar.valid and pass_s(3);
    in_o.ar.ready <= out_i.ar.ready and pass_s(3);
    in_o.r.valid <= out_i.r.valid and pass_s(4);
    out_o.r.ready <= in_i.r.ready and pass_s(4);
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_amba, nsl_video, nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_video.pixel_stream.all;
use nsl_video.vdma.all;

-- Writer -> RAM -> reader round trip, for two line repeat factors.
--
-- Every frame is 4 lines of 23 two-pixel RGB beats (69 bytes, last
-- beat half full) in a 96-byte stride. Frame buffers are spaced by
-- exactly one frame, starting off the burst alignment, so a line the
-- writer failed to drop would land in the next buffer.
--
-- Writer stimulus sends, in order: garbage before any SOF, frame A
-- (good), frame B (one ERROR line), frame C (cut short by the SOF of
-- frame D), frame D (good), frame E (one line longer than the stride,
-- one line too many). Then buffers A, D, E and D again are read back
-- and checked.
entity tb is
end entity;

architecture arch of tb is

  constant mem_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32,
                               data_bus_width => 128,
                               max_length => 16,
                               burst => true,
                               size => true);
  constant pix_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 2, components => 3, keep => true);
  constant scfg_c : nsl_amba.axi4_stream.config_t := pix_config_c.stream;

  constant width_px_c : natural := 23;
  constant line_bytes_c : natural := width_px_c * 3;
  constant long_px_c : natural := 40;
  constant height_c : natural := 4;
  constant stride_c : natural := 96;
  constant frame_bytes_c : natural := height_c * stride_c;
  constant buf0_c : natural := 16#30#;

  function buf_base(i : natural) return unsigned
  is
  begin
    return to_unsigned(buf0_c + i * frame_bytes_c, 32);
  end function;

  function pix(fid, y, i : natural) return byte
  is
  begin
    return std_ulogic_vector(to_unsigned((fid * 53 + y * 29 + i * 7 + 1) mod 256, 8));
  end function;

  type status_vector is array (natural range <>) of frame_status_t;
  constant expected_c : status_vector(0 to 4) := (
    -- complete, truncated, line_error, overflow, bus_error
    ('1', '0', '0', '0', '0'),
    ('0', '0', '1', '0', '0'),
    ('0', '1', '0', '0', '0'),
    ('1', '0', '0', '0', '0'),
    ('0', '0', '0', '1', '0')
    );

  type job_t is
  record
    fid : natural;
    buf : natural;
  end record;
  type job_vector is array (natural range <>) of job_t;
  constant jobs_c : job_vector(0 to 3) := ((0, 0), (3, 3), (4, 2), (3, 3));

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

begin

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

  instances: for g in 0 to 1
  generate
    constant repeat_c : positive := g + 1;

    signal in_s, out_s : nsl_video.pixel_stream.bus_t;
    signal w_mem_s, r_mem_s, w_ram_s, r_ram_s, ram_s : nsl_amba.axi4_mm.bus_t;
    signal w_base_s : unsigned(31 downto 0) := (others => '0');
    signal r_base_s : unsigned(31 downto 0) := (others => '0');
    signal w_start_s, w_done_s, r_ready_s, r_done_s, r_start_s : std_ulogic;
    signal w_status_s, r_status_s : frame_status_t;
    signal writer_finished_s : boolean := false;
    signal starts_s : natural := 0;
    signal reads_done_s : natural := 0;
    signal check_done_s, read_done_s : boolean := false;
  begin

    writer: nsl_video.vdma.vdma_writer
      generic map(
        mem_config_c => mem_config_c,
        stream_config_c => pix_config_c,
        burst_length_l2_c => 2,
        buffer_depth_c => 8
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        base_i => w_base_s,
        stride_i => to_unsigned(stride_c, 32),
        max_height_i => to_unsigned(height_c, 16),

        start_o => w_start_s,
        done_o => w_done_s,
        status_o => w_status_s,

        stream_i => in_s.m,
        stream_o => in_s.s,

        mem_o => w_mem_s.m,
        mem_i => w_mem_s.s
        );

    reader: nsl_video.vdma.vdma_reader
      generic map(
        mem_config_c => mem_config_c,
        stream_config_c => pix_config_c,
        burst_length_l2_c => 2,
        buffer_depth_c => 16,
        line_repeat_c => repeat_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        base_i => r_base_s,
        stride_i => to_unsigned(stride_c, 32),
        width_i => to_unsigned(line_bytes_c, 16),
        height_i => to_unsigned(height_c, 16),
        start_i => r_start_s,
        ready_o => r_ready_s,

        done_o => r_done_s,
        status_o => r_status_s,

        mem_o => r_mem_s.m,
        mem_i => r_mem_s.s,

        stream_o => out_s.m,
        stream_i => out_s.s
        );

    w_stall: entity work.mm_staller
      generic map(
        config_c => mem_config_c,
        seed_c => 11 + g,
        pass_permille_c => 600
        )
      port map(
        clock_i => clock_s,
        in_i => w_mem_s.m,
        in_o => w_mem_s.s,
        out_o => w_ram_s.m,
        out_i => w_ram_s.s
        );

    r_stall: entity work.mm_staller
      generic map(
        config_c => mem_config_c,
        seed_c => 23 + g,
        pass_permille_c => 700
        )
      port map(
        clock_i => clock_s,
        in_i => r_mem_s.m,
        in_o => r_mem_s.s,
        out_o => r_ram_s.m,
        out_i => r_ram_s.s
        );

    -- The RAM model serves one master: the writer owns the write
    -- channels, the reader owns the read channels.
    ram_s.m.aw <= w_ram_s.m.aw;
    ram_s.m.w <= w_ram_s.m.w;
    ram_s.m.b <= w_ram_s.m.b;
    ram_s.m.ar <= r_ram_s.m.ar;
    ram_s.m.r <= r_ram_s.m.r;
    w_ram_s.s <= ram_s.s;
    r_ram_s.s <= ram_s.s;

    ram: nsl_amba.ram.axi4_mm_full_ram
      generic map(
        config_c => mem_config_c,
        byte_size_l2_c => 12
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        axi_i => ram_s.m,
        axi_o => ram_s.s
        );

    start_count: process(clock_s) is
    begin
      if rising_edge(clock_s) and w_start_s = '1' then
        starts_s <= starts_s + 1;
      end if;
    end process;

    stim: process is
      variable s1 : positive := 5 + g;
      variable s2 : positive := 1234;

      procedure gap is
        variable x : real;
      begin
        uniform(s1, s2, x);
        if x < 0.3 then
          for i in 0 to integer(x * 10.0)
          loop
            wait until falling_edge(clock_s);
          end loop;
        end if;
      end procedure;

      procedure line(fid, y, npx : natural;
                     sof, eof, err : boolean := false) is
        constant len : natural := npx * 3;
        constant beats : natural := (len + 5) / 6;
        variable data : byte_string(0 to 5);
        variable keep : std_ulogic_vector(0 to 5);
        variable user : std_ulogic_vector(2 downto 0);
      begin
        for b in 0 to beats-1
        loop
          for i in 0 to 5
          loop
            if b * 6 + i < len then
              data(i) := pix(fid, y, b * 6 + i);
              keep(i) := '1';
            else
              data(i) := x"00";
              keep(i) := '0';
            end if;
          end loop;
          user := (others => '0');
          if b = 0 and sof then
            user(user_sof_c) := '1';
          end if;
          if b = beats - 1 and eof then
            user(user_eof_c) := '1';
          end if;
          if b = beats - 1 and err then
            user(user_error_c) := '1';
          end if;
          gap;
          nsl_amba.axi4_stream.send(scfg_c, clock_s, in_s.s, in_s.m,
                                    bytes => data, keep => keep, user => user,
                                    last => b = beats - 1);
        end loop;
      end procedure;

      procedure frame(fid, buf, lines : natural;
                      eof : boolean := true;
                      err_line : integer := -1;
                      long_line : integer := -1) is
        variable npx : natural;
      begin
        while starts_s < fid
        loop
          wait until falling_edge(clock_s);
        end loop;
        w_base_s <= buf_base(buf);
        for y in 0 to lines-1
        loop
          npx := width_px_c;
          if y = long_line then
            npx := long_px_c;
          end if;
          line(fid, y, npx,
               sof => y = 0,
               eof => eof and y = lines - 1,
               err => y = err_line);
        end loop;
      end procedure;

    begin
      in_s.m <= nsl_amba.axi4_stream.transfer_defaults(scfg_c);
      w_base_s <= buf_base(7);
      wait until reset_n_s = '1';
      wait until falling_edge(clock_s);

      -- Nothing here has a SOF, all of it goes to the bin.
      line(9, 2, width_px_c);
      line(9, 3, 5, eof => true);

      frame(0, 0, height_c);
      frame(1, 1, height_c, err_line => 1);
      frame(2, 2, 2, eof => false);
      frame(3, 3, height_c);
      frame(4, 2, height_c + 1, long_line => height_c - 1);

      wait;
    end process;

    writer_check: process is
    begin
      for f in expected_c'range
      loop
        wait until rising_edge(clock_s) and w_done_s = '1';
        log_info("Writer " & integer'image(g) & " frame " & integer'image(f)
                 & " complete=" & to_string(w_status_s.complete)
                 & " truncated=" & to_string(w_status_s.truncated)
                 & " line_error=" & to_string(w_status_s.line_error)
                 & " overflow=" & to_string(w_status_s.overflow)
                 & " bus_error=" & to_string(w_status_s.bus_error));
        assert w_status_s = expected_c(f)
          report "Unexpected writer status for frame " & integer'image(f)
          severity failure;
      end loop;
      writer_finished_s <= true;
      wait;
    end process;

    read_cmd: process is
    begin
      r_start_s <= '0';
      wait until writer_finished_s;
      for j in jobs_c'range
      loop
        wait until falling_edge(clock_s);
        while r_ready_s /= '1'
        loop
          wait until falling_edge(clock_s);
        end loop;
        r_base_s <= buf_base(jobs_c(j).buf);
        r_start_s <= '1';
        wait until falling_edge(clock_s);
        r_start_s <= '0';
        wait until rising_edge(clock_s) and r_done_s = '1';
        assert r_status_s.complete = '1' and r_status_s.bus_error = '0'
          report "Reader reported an error"
          severity failure;
      end loop;
      read_done_s <= true;
      wait;
    end process;

    read_check: process is
      variable s1 : positive := 77 + g;
      variable s2 : positive := 99;
      variable x : real;
      variable beat : nsl_amba.axi4_stream.master_t;
      variable lines, beats, len, y : natural;
      variable u : std_ulogic_vector(2 downto 0);
      variable k : std_ulogic_vector(0 to 5);
      variable d : byte_string(0 to 5);
    begin
      out_s.s <= nsl_amba.axi4_stream.accept(scfg_c, false);
      wait until reset_n_s = '1';

      lines := height_c * repeat_c;
      len := line_bytes_c;
      beats := (len + 5) / 6;

      for j in jobs_c'range
      loop
        for l in 0 to lines-1
        loop
          y := l / repeat_c;
          for b in 0 to beats-1
          loop
            loop
              wait until falling_edge(clock_s);
              uniform(s1, s2, x);
              out_s.s <= nsl_amba.axi4_stream.accept(scfg_c, x < 0.5);
              wait until rising_edge(clock_s);
              exit when out_s.m.valid = '1' and out_s.s.ready = '1';
            end loop;
            beat := out_s.m;

            u := nsl_amba.axi4_stream.user(scfg_c, beat);
            k := nsl_amba.axi4_stream.keep(scfg_c, beat);
            d := nsl_amba.axi4_stream.bytes(scfg_c, beat);

            assert (u(user_sof_c) = '1') = (l = 0 and b = 0)
              report "Bad SOF, job " & integer'image(j) & " line " & integer'image(l)
              & " beat " & integer'image(b)
              severity failure;
            assert (u(user_eof_c) = '1') = (l = lines - 1 and b = beats - 1)
              report "Bad EOF, job " & integer'image(j) & " line " & integer'image(l)
              & " beat " & integer'image(b)
              severity failure;
            assert u(user_error_c) = '0'
              report "Unexpected ERROR"
              severity failure;
            assert nsl_amba.axi4_stream.is_last(scfg_c, beat) = (b = beats - 1)
              report "Bad TLAST, job " & integer'image(j) & " line " & integer'image(l)
              & " beat " & integer'image(b)
              severity failure;

            for i in 0 to 5
            loop
              if b * 6 + i < len then
                assert k(i) = '1'
                  report "Missing TKEEP" severity failure;
                assert d(i) = pix(jobs_c(j).fid, y, b * 6 + i)
                  report "Bad data, job " & integer'image(j) & " line " & integer'image(l)
                  & " byte " & integer'image(b * 6 + i)
                  & ": " & to_string(d(i)) & ", expected "
                  & to_string(pix(jobs_c(j).fid, y, b * 6 + i))
                  severity failure;
              else
                assert k(i) = '0'
                  report "Extra TKEEP" severity failure;
              end if;
            end loop;
          end loop;
        end loop;
        log_info("Reader " & integer'image(g) & " job " & integer'image(j) & " checked");
      end loop;

      wait until falling_edge(clock_s);
      out_s.s <= nsl_amba.axi4_stream.accept(scfg_c, false);
      check_done_s <= true;
      wait;
    end process;

    done_s(g) <= '1' when check_done_s and read_done_s else '0';
  end generate;

end architecture;
