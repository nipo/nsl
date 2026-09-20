library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_amba, nsl_ext_ram;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;
use nsl_ext_ram.ddr3.all;

-- Walks a DDR3 part through the serialiser PHY, after finding where in
-- the captured stream its answers land.
--
-- The whole stack is here rather than the AXI wrapper, because this
-- PHY needs a clock pair the wrapper does not carry and a read offset
-- that has to be trained.  The training is the same sweep a board
-- performs: run a region small enough to be quick at each offset and
-- keep the first one that comes back without errors.  That the sweep
-- has exactly one answer, and that it is where the part's CAS latency
-- and the two serialiser pipelines put it, is what this bench is for.
--
-- The clock pair is what the argument in the PHY's header rests on:
-- the strobe leaves on the same clock as CK, and the data a quarter of
-- a memory period behind it.  Break either and the part model's strobe
-- centring check fires.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: dram_part_t := as4c128m8d3lb_c;
  -- DDR3-800, which is what a serialiser eight slots wide reaches with
  -- a controller clock a fabric is comfortable at.
  constant tck_ps_c: natural := 2500;
  constant timing_c: dram_timing_t := timings(part_c, tck_ps_c);
  constant dfi_config_c: nsl_ext_ram.dfi.config_t := dfi_config(part_c);
  constant script_c: init_script_t
    := ddr3_init_script(part_c, timing_c, dfi_config_c.phase_count);

  constant phase_c: natural := phase_count(part_c);
  constant tck_c: time := tck_ps_c * 1 ps;
  constant controller_period_c: time := phase_c * tck_c;

  constant axi_config_c: config_t := axi_config(part_c);
  constant lane_count_c: natural := part_c.dq_width / 8;

  -- Enough to cross rows and banks for the walk, and small enough that
  -- one pass at each read offset is not a whole simulation.
  constant region_byte_l2_c: natural := 13;
  constant probe_byte_l2_c: natural := 6;
  constant offset_count_c: natural := 128;
  -- More steps than any delay line here carries, so a sweep covers a
  -- whole turn of it whatever the family.
  constant tap_try_c: natural := 64;

  signal clock_s: std_ulogic := '0';
  signal fast_clock_s: std_ulogic := '0';
  signal data_clock_s: std_ulogic := '0';
  signal ref_clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal axi_s: bus_t;
  signal ready_s: std_ulogic;

  signal cmd_s: cmd_t;
  signal cmd_ack_s: cmd_ack_t;
  signal wdata_s: wdata_t;
  signal wdata_ack_s: wdata_ack_t;
  signal rdata_s: rdata_t;
  signal rdata_ack_s: rdata_ack_t;

  signal dfi_master_s: nsl_ext_ram.dfi.master_t;
  signal dfi_slave_s: nsl_ext_ram.dfi.slave_t;

  signal read_offset_s: unsigned(6 downto 0) := (others => '0');
  signal dq_shift_s: std_ulogic_vector(part_c.dq_width - 1 downto 0)
    := (others => '0');
  signal dq_mark_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);
  signal level_answer_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  signal probe_reset_n_s: std_ulogic := '0';
  signal probe_start_s, probe_done_s: std_ulogic;
  signal probe_master_s: master_t;
  signal probe_errors_s: unsigned(31 downto 0);

  signal walk_start_s, walk_done_s: std_ulogic;
  signal walk_master_s: master_t;
  signal walk_errors_s: unsigned(31 downto 0);
  signal walk_first_s: unsigned(axi_config_c.address_width - 1 downto 0);

  signal walking_s: boolean := false;

  signal ck_s: nsl_io.diff.diff_pair;
  signal cke_s, cs_n_s, ras_n_s, cas_n_s, we_n_s: std_ulogic;
  signal odt_s, ram_reset_n_s: std_ulogic;
  signal ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal a_s: unsigned(address_width(part_c) - 1 downto 0);
  signal dm_s: std_ulogic_vector(lane_count_c - 1 downto 0);

  signal dqs_phy_s, dqs_n_phy_s, dqs_model_s:
    nsl_io.io.tristated_vector(lane_count_c - 1 downto 0);
  signal dqs_wire_s: std_logic_vector(lane_count_c - 1 downto 0);
  signal dqs_value_s: std_ulogic_vector(lane_count_c - 1 downto 0);

  signal dq_phy_s, dq_model_s:
    nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal dq_wire_s: std_logic_vector(part_c.dq_width - 1 downto 0);
  signal dq_value_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  -- Datasheet constraints the model saw broken.  They are
  -- reported as they happen; the run has to fail on them too.
  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after controller_period_c / 2 when not stopped_s
             else '0';
  fast_clock_s <= (not fast_clock_s) after tck_c / 2 when not stopped_s
                  else '0';
  -- A quarter of a memory period behind the one the strobe leaves on
  data_clock_s <= transport fast_clock_s after tck_c / 4;
  ref_clock_s <= (not ref_clock_s) after 2500 ps when not stopped_s
                 else '0';

  reset_n_s <= '1' after 3 * controller_period_c;

  dqs_wiring: for i in dqs_wire_s'range
  generate
    dqs_wire_s(i) <= nsl_io.io.to_logic(dqs_phy_s(i));
    dqs_wire_s(i) <= nsl_io.io.to_logic(dqs_model_s(i));
  end generate;
  dqs_value_s <= std_ulogic_vector(to_x01(dqs_wire_s));

  dq_wiring: for i in dq_wire_s'range
  generate
    dq_wire_s(i) <= nsl_io.io.to_logic(dq_phy_s(i));
    dq_wire_s(i) <= nsl_io.io.to_logic(dq_model_s(i));
  end generate;
  dq_value_s <= std_ulogic_vector(to_x01(dq_wire_s));

  axi_s.m <= walk_master_s when walking_s else probe_master_s;

  probe: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => probe_byte_l2_c,
      burst_length_c => 4,
      seed_c => 51,
      scramble_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => probe_reset_n_s,
      start_i => probe_start_s,
      axi_o => probe_master_s,
      axi_i => axi_s.s,
      busy_o => open,
      done_o => probe_done_s,
      error_count_o => probe_errors_s,
      first_error_address_o => open
      );

  walk: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => 4,
      seed_c => 4242,
      scramble_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      start_i => walk_start_s,
      axi_o => walk_master_s,
      axi_i => axi_s.s,
      busy_o => open,
      done_o => walk_done_s,
      error_count_o => walk_errors_s,
      first_error_address_o => walk_first_s
      );

  adapter: nsl_ext_ram.frontend.axi4_mm_burst_adapter
    generic map(
      axi_config_c => axi_config_c,
      cycle_byte_count_c => cycle_byte_count(part_c),
      burst_cycle_count_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      cmd_o => cmd_s,
      cmd_i => cmd_ack_s,
      wdata_o => wdata_s,
      wdata_i => wdata_ack_s,
      rdata_i => rdata_s,
      rdata_o => rdata_ack_s,

      ready_i => ready_s
      );

  core: nsl_ext_ram.dram.dram_core
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      script_c => script_c,
      burst_length_l2_c => part_c.prefetch_l2,
      keep_row_open_c => true,
      -- What ddr3_controller gives the core, so the PHY is walked the
      -- way a design drives it: column commands every tCCD, reads
      -- announced by a level that stays up over several of them, and
      -- write bursts laid back to back with no preamble between.
      read_ahead_c => 11,
      write_overlap_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      wdata_i => wdata_s,
      wdata_o => wdata_ack_s,
      rdata_o => rdata_s,
      rdata_i => rdata_ack_s,

      ready_o => ready_s,

      dfi_o => dfi_master_s,
      dfi_i => dfi_slave_s
      );

  dut: nsl_ext_ram.ddr3_io.ddr3_phy_serdes
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      -- What a family of exact clocks and behavioural serialisers
      -- comes to.  The offset is checked rather than taken: the sweep
      -- below has to land on it, which is what says the arithmetic in
      -- the PHY is the arithmetic the part answers to.
      board_c => nsl_ext_ram.ddr3_io.serdes_simulation_board_c
      )
    port map(
      clock_i => clock_s,
      fast_clock_i => fast_clock_s,
      data_clock_i => data_clock_s,
      -- Behavioural serialisers take two clock pairs on one pin, so
      -- the shifted parallel clock is the plain one and the crossing
      -- the PHY makes its data words go through is a cycle inside one
      -- domain.  A Gowin build is what the second clock is there for.
      shifted_clock_i => clock_s,
      delay_ref_clock_i => ref_clock_s,
      reset_n_i => reset_n_s,

      dfi_i => dfi_master_s,
      dfi_o => dfi_slave_s,

      read_offset_i => read_offset_s,
      dq_delay_shift_i => dq_shift_s,
      dq_delay_mark_o => dq_mark_s,
      write_level_answer_o => level_answer_s,

      ck_o => ck_s,
      cke_o => cke_s,
      cs_n_o => cs_n_s,
      ras_n_o => ras_n_s,
      cas_n_o => cas_n_s,
      we_n_o => we_n_s,
      ba_o => ba_s,
      a_o => a_s,
      odt_o => odt_s,
      ram_reset_n_o => ram_reset_n_s,

      dm_o => dm_s,
      dqs_o => dqs_phy_s,
      dqs_n_o => dqs_n_phy_s,
      dq_o => dq_phy_s,
      dq_i => dq_value_s
      );

  model: nsl_ext_ram.simulation.ddr3_model
    generic map(
      part_c => part_c
      )
    port map(
      ck_i => ck_s.p,
      reset_n_i => ram_reset_n_s,
      cke_i => cke_s,
      cs_n_i => cs_n_s,
      ras_n_i => ras_n_s,
      cas_n_i => cas_n_s,
      we_n_i => we_n_s,
      ba_i => ba_s,
      a_i => a_s,
      odt_i => odt_s,
      dm_i => dm_s,
      dqs_i => dqs_value_s,
      dqs_o => dqs_model_s,
      dq_i => dq_value_s,
      dq_o => dq_model_s,
      violation_count_o => violation_count_s
      );

  watchdog: process is
  begin
    wait for 100 ms;
    assert stopped_s
      report "watchdog fired, controller or tester is stuck"
      severity failure;
    wait;
  end process;

  stim: process is
    variable found_offset: integer := -1;
    variable found_tap: integer := -1;
    variable eye: natural := 0;

    procedure probe_once is
    begin
      -- The walker stops where it finishes, so each pass gets a fresh
      -- one rather than one instance per point of the sweep.
      probe_start_s <= '0';
      probe_reset_n_s <= '0';
      wait for 4 * controller_period_c;
      probe_reset_n_s <= '1';

      wait until falling_edge(clock_s);
      probe_start_s <= '1';
      wait until probe_done_s = '1';
      wait until falling_edge(clock_s);
      probe_start_s <= '0';
    end procedure;

    procedure delay_step is
    begin
      wait until falling_edge(clock_s);
      dq_shift_s <= (others => '1');
      wait until falling_edge(clock_s);
      dq_shift_s <= (others => '0');
    end procedure;

    -- Back to the shortest tap, which is the only position on the line
    -- that can be named without knowing how long it is.  The PHY left
    -- the lines where its board record asked for, so a sweep that
    -- wants to report absolute taps starts by undoing that.
    procedure delay_rewind is
    begin
      while dq_mark_s /= (dq_mark_s'range => '1')
      loop
        delay_step;
      end loop;
    end procedure;
  begin
    probe_start_s <= '0';
    walk_start_s <= '0';

    wait until ready_s = '1';
    report "controller ready at " & time'image(now);

    -- Read training, both dimensions.  A part answers its CAS latency
    -- after the command and the serialisers on both sides add
    -- pipelines, none of which is knowable from a datasheet: that is
    -- the offset, and it moves in whole beats.  Inside a beat, the
    -- part launches its data on the edge that carries its strobe,
    -- which is the edge the bus is sampled on, so the eye has to be
    -- walked off it: that is the delay line, and it moves in taps.
    --
    -- The delay is the outer loop because it is the dimension that has
    -- to be right for the offset to mean anything, and it starts at
    -- tap one rather than tap zero: with the line adding nothing, the
    -- bus is sampled on the very edge the part launched it on.  A
    -- point that answers there answers by luck.
    delay_rewind;
    delay_step;

    taps: for tap in 1 to tap_try_c - 1
    loop
      for offset in 0 to offset_count_c - 1
      loop
        wait until falling_edge(clock_s);
        read_offset_s <= to_unsigned(offset, read_offset_s'length);
        probe_once;
        if probe_errors_s = 0 then
          found_offset := offset;
          found_tap := tap;
          exit taps;
        end if;
      end loop;
      delay_step;
    end loop;

    assert found_offset >= 0
      report "no offset and delay bring a burst back whole"
      severity failure;

    report "read answers at offset " & integer'image(found_offset)
      & ", at tap " & integer'image(found_tap);

    -- How much of the line the answer survives, which is the eye
    -- measured in taps of that line.  A window one step wide would
    -- mean the sweep stopped on an edge rather than inside an eye.
    eye := 1;
    while eye < tap_try_c
    loop
      delay_step;
      probe_once;
      exit when probe_errors_s /= 0;
      eye := eye + 1;
    end loop;

    report "the eye holds for " & integer'image(eye) & " taps";

    assert eye >= 4
      report "the read eye is " & integer'image(eye)
      & " taps wide, which is an edge and not an eye"
      severity failure;

    -- Sitting one step past the end of the window; carry on round the
    -- line, which tap_try_c steps is a whole number of turns of, and
    -- stop in the middle of it.
    for k in 1 to tap_try_c - (eye - eye / 2)
    loop
      delay_step;
    end loop;

    wait until falling_edge(clock_s);
    walking_s <= true;
    walk_start_s <= '1';

    wait until walk_done_s = '1';

    assert walk_errors_s = 0
      report "walk found " & integer'image(to_integer(walk_errors_s))
      & " errors, first at address "
      & integer'image(to_integer(walk_first_s))
      severity failure;

    report "walk done at " & time'image(now) & ", "
      & integer'image(to_integer(walk_errors_s)) & " errors";

    assert violation_count_s = 0
      report integer'image(violation_count_s)
      & " datasheet constraints were broken on the part's pins"
      severity failure;

    stopped_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
