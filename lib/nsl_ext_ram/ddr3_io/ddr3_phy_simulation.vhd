library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

-- Each controller cycle, the whole cycle's worth of pin activity is
-- scheduled at once: the clock toggles once per phase, command slots
-- are driven half a tick before the edge that samples them, and a
-- write burst is laid out CAS write latency after its command with the
-- strobe a quarter tick behind the data so it lands in the middle of
-- the eye.
--
-- Read data is captured on the part's own strobe, delayed a quarter
-- tick for the same reason.  There is no training and no delay line:
-- this is the PHY a simulation uses to exercise a controller against a
-- memory model.
--
-- Column commands may follow each other every tCCD, which is one
-- controller cycle here, so both directions have to hold several
-- bursts at once: reads are announced by a level whose every high
-- cycle is one cycle of answer, and a write burst that follows another
-- goes out with no preamble between the two.
entity ddr3_phy is
  generic(
    part_c: dram_part_t;
    timing_c: dram_timing_t;
    dfi_config_c: config_t;
    tck_ps_c: natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    dfi_i: in master_t;
    dfi_o: out slave_t;

    ck_o: out nsl_io.diff.diff_pair;
    cke_o: out std_ulogic;
    cs_n_o: out std_ulogic;
    ras_n_o: out std_ulogic;
    cas_n_o: out std_ulogic;
    we_n_o: out std_ulogic;
    ba_o: out unsigned;
    a_o: out unsigned;
    odt_o: out std_ulogic;
    ram_reset_n_o: out std_ulogic;

    dm_o: out std_ulogic_vector;
    dqs_o: out nsl_io.io.tristated_vector;
    dqs_i: in std_ulogic_vector;
    dq_o: out nsl_io.io.tristated_vector;
    dq_i: in std_ulogic_vector
    );
end entity;

architecture beh of ddr3_phy is

  constant tck_c: time := tck_ps_c * 1 ps;
  constant phase_c: natural := dfi_config_c.phase_count;
  constant lane_count_c: natural := dfi_config_c.dq_byte_count;
  constant slot_count_c: natural := slot_count(dfi_config_c);

  -- Command slots settle half a tick before the edge that samples
  -- them, so the part sees a phase zero command one tick into the
  -- cycle.  A write burst starts CAS write latency after that, and can
  -- well run past the end of the cycle.
  constant write_start_c: time := (1 + timing_c.cwl) * tck_c;

  -- Read bursts announced and not yet answered, and answers captured
  -- and not yet handed over.  A read is announced a whole round trip
  -- before its answer, so this has to be at least as deep as the
  -- announcement queue of ddr3_phy_serdes, which is what a design is
  -- held to.
  constant capture_depth_c: natural := 16;

  type burst_vector is array (natural range <>)
    of data_vector(0 to max_slot_count_c - 1);

  signal dqs_wire_s: std_ulogic_vector(dqs_i'range);
  signal dqs_late_s: std_ulogic_vector(dqs_i'range);

  signal rddata_s: data_vector(0 to max_slot_count_c - 1);
  signal rddata_valid_s: std_ulogic := '0';

begin

  assert dfi_config_c.edge_count = 2
    report "ddr3_phy: DDR3 carries two data words per tick"
    severity failure;

  assert phase_c * dfi_config_c.edge_count = 2 ** part_c.prefetch_l2
    report "ddr3_phy: one controller cycle has to carry a whole burst"
    severity failure;

  dqs_wire_s <= dqs_i;
  dqs_late_s <= transport dqs_wire_s after tck_c / 4;

  drive: process(clock_i, reset_n_i) is
    variable cmd: command_t;
    variable slot: data_t;
    variable beat_at: time;
    -- Whether last cycle put a burst out, which is what says the one
    -- this cycle carries follows it with nothing in between.
    variable writing: boolean := false;
  begin
    if reset_n_i = '0' then
      writing := false;
      cke_o <= '0';
      cs_n_o <= '1';
      ram_reset_n_o <= '0';
      odt_o <= '0';
      for i in dq_o'range
      loop
        dq_o(i) <= nsl_io.io.tristated_z;
      end loop;
      for i in dqs_o'range
      loop
        dqs_o(i) <= nsl_io.io.tristated_z;
      end loop;

    elsif rising_edge(clock_i) then
      ram_reset_n_o <= dfi_i.reset_n;

      -- The clock the part samples everything against.
      for phase in 0 to phase_c - 1
      loop
        ck_o.p <= transport '1' after phase * tck_c;
        ck_o.n <= transport '0' after phase * tck_c;
        ck_o.p <= transport '0' after phase * tck_c + tck_c / 2;
        ck_o.n <= transport '1' after phase * tck_c + tck_c / 2;
      end loop;

      -- Command slots settle half a tick before the edge that samples
      -- them, which leaves the part half a tick of setup and half of
      -- hold.
      for phase in 0 to phase_c - 1
      loop
        cmd := dfi_i.command(phase);
        beat_at := phase * tck_c + tck_c / 2;

        cke_o <= transport cmd.cke after beat_at;
        cs_n_o <= transport cmd.cs_n after beat_at;
        ras_n_o <= transport cmd.ras_n after beat_at;
        cas_n_o <= transport cmd.cas_n after beat_at;
        we_n_o <= transport cmd.we_n after beat_at;
        ba_o <= transport bank(dfi_config_c, cmd) after beat_at;
        a_o <= transport resize(address(dfi_config_c, cmd), a_o'length)
               after beat_at;
        odt_o <= transport cmd.odt after beat_at;
      end loop;

      -- A write burst, or nothing: leaving the data pins alone keeps
      -- the waveform an earlier cycle scheduled, which a burst that
      -- runs past the cycle boundary depends on.
      if dfi_i.wrdata_en(0) = '1' then
        -- Preamble: the strobe is pulled low over the tick ahead of
        -- the burst, unless the burst before it is still going out.
        -- DDR3 has no preamble between bursts that follow each other,
        -- the strobe simply keeps toggling, and one written here would
        -- land on the last two beats of the burst before instead.
        if not writing then
          for lane in 0 to lane_count_c - 1
          loop
            dqs_o(dqs_o'low + lane)
              <= transport nsl_io.io.to_tristated('0', '1')
                 after write_start_c - tck_c + tck_c / 4;
          end loop;
        end if;

        for step in 0 to slot_count_c - 1
        loop
          slot := dfi_i.wrdata(step);
          beat_at := write_start_c + (step * tck_c) / 2;

          for lane in 0 to lane_count_c - 1
          loop
            for b in 0 to 7
            loop
              dq_o(dq_o'low + lane * 8 + b)
                <= transport nsl_io.io.to_tristated(slot.value(lane)(b), '1')
                   after beat_at;
            end loop;

            dm_o(dm_o'low + lane) <= transport slot.mask(lane) after beat_at;

            -- The strobe edge sits a quarter tick into the eye.
            if step mod 2 = 0 then
              dqs_o(dqs_o'low + lane)
                <= transport nsl_io.io.to_tristated('1', '1')
                   after beat_at + tck_c / 4;
            else
              dqs_o(dqs_o'low + lane)
                <= transport nsl_io.io.to_tristated('0', '1')
                   after beat_at + tck_c / 4;
            end if;
          end loop;
        end loop;

        -- Letting go of the bus behind the burst.  A burst following
        -- this one takes these back: its own first beat falls on the
        -- very edge this releases on, and it is scheduled a cycle
        -- later, so it supersedes what is pending there.
        beat_at := write_start_c + (slot_count_c * tck_c) / 2;
        for i in dq_o'range
        loop
          dq_o(i) <= transport nsl_io.io.tristated_z after beat_at;
        end loop;
        for i in dqs_o'range
        loop
          dqs_o(i) <= transport nsl_io.io.tristated_z
                      after beat_at + tck_c / 4;
        end loop;
      end if;

      writing := dfi_i.wrdata_en(0) = '1';
    end if;
  end process;

  capture: process(clock_i, dqs_late_s, reset_n_i) is
    -- Reads announced and not yet answered.  DFI states rddata_en as a
    -- level high for a cycle per cycle of answer, so two cycles of it
    -- announce two bursts: what is counted here is cycles of the level
    -- and not edges of it, which is the only reading that lets reads
    -- follow each other every tCCD.
    variable pending: natural := 0;
    variable started: boolean := false;
    variable beat: natural := 0;
    variable collected: data_vector(0 to max_slot_count_c - 1);
    -- Bursts caught off the strobe and not yet handed to the
    -- controller, which takes one a cycle.
    variable queue: burst_vector(0 to capture_depth_c - 1);
    variable fill, drain, count: natural := 0;
    variable previous: std_ulogic_vector(dqs_i'range) := (others => 'U');
    variable value: byte_string(0 to max_dq_byte_count_c - 1);
  begin
    if reset_n_i = '0' then
      pending := 0;
      started := false;
      beat := 0;
      fill := 0;
      drain := 0;
      count := 0;
      rddata_valid_s <= '0';

    else
      if dqs_late_s /= previous then
        -- A burst that follows a gap starts on the first rising edge
        -- and not on the release from high impedance before it, which
        -- the part holds the strobe low through.  A burst that follows
        -- another has no preamble in front of it, and the rising edge
        -- that starts it is the edge after the last beat of the one
        -- before: the same rule finds both.
        if pending /= 0 and not started
          and dqs_late_s(dqs_late_s'low) = '1' then
          started := true;
          beat := 0;
        end if;

        if started then
          value := (others => dontcare_byte_c);
          for lane in 0 to lane_count_c - 1
          loop
            value(lane) := dq_i(dq_i'low + lane * 8 + 7
                                downto dq_i'low + lane * 8);
          end loop;
          collected(beat) := data(dfi_config_c,
                                  value(0 to lane_count_c - 1));

          beat := beat + 1;
          if beat = slot_count_c then
            started := false;
            pending := pending - 1;

            assert count /= capture_depth_c
              report "ddr3_phy: more read answers are in flight than the"
              & " capture queue holds"
              severity failure;

            queue(fill) := collected;
            fill := (fill + 1) mod capture_depth_c;
            count := count + 1;
          end if;
        end if;
        previous := dqs_late_s;
      end if;

      if rising_edge(clock_i) then
        rddata_valid_s <= '0';

        if count /= 0 then
          rddata_s <= queue(drain);
          rddata_valid_s <= '1';
          drain := (drain + 1) mod capture_depth_c;
          count := count - 1;
        end if;

        if dfi_i.rddata_en(0) = '1' then
          assert pending /= capture_depth_c
            report "ddr3_phy: more reads are announced than the capture"
            & " queue holds"
            severity failure;
          pending := pending + 1;
        end if;
      end if;
    end if;
  end process;

  answer: process(rddata_s, rddata_valid_s) is
  begin
    dfi_o <= slave_defaults(dfi_config_c);
    dfi_o.rddata <= rddata_s;
    dfi_o.rddata_valid <= rddata_valid_s;
    dfi_o.init_complete <= '1';
  end process;

end architecture;
