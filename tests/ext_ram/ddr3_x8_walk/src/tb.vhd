library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_amba, nsl_ext_ram;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.dram.all;
use nsl_ext_ram.ddr3.all;

-- Walks an x8 DDR3 part in address order over a region wide enough to
-- leave the open row and the open bank several times, and measures
-- what a burst costs.
--
-- The region is taken from the controller's own address map rather
-- than guessed: the map puts the bank bits under the row bits, so a
-- linear walk changes bank every page and row every eight pages, and
-- four rows' worth of address space crosses three row boundaries and
-- thirty-one bank boundaries.  The walk is long enough for several
-- refresh intervals to expire inside the write pass, so refreshes land
-- between an activate and the writes that follow it.
--
-- One pass walks the bottom of the part and the next the top, which is
-- the same walk with every row bit set: a walk of the whole part
-- differs from these two only in how long it takes.
--
-- The counts the bench reports are the ones a part-sized walk is
-- extrapolated from: controller cycles between the first write address
-- and the last write response, over the bursts that carried them.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: dram_part_t := as4c128m8d3lb_c;
  -- DDR3-800, the rate the board this part sits on runs at.
  constant tck_ps_c: natural := 2500;
  constant phase_c: natural := phase_count(part_c);
  constant controller_period_c: time := phase_c * tck_ps_c * 1 ps;

  constant dfi_config_c: nsl_ext_ram.dfi.config_t := dfi_config(part_c);
  constant layout_c: layout_t := layout(part_c, dfi_config_c,
                                        part_c.prefetch_l2);

  constant axi_config_c: nsl_amba.axi4_mm.config_t := axi_config(part_c);
  constant beat_byte_c: natural := cycle_byte_count(part_c);
  constant lane_count_c: natural := part_c.dq_width / 8;

  -- Four rows of one bank column, which is four times eight pages.
  constant region_byte_l2_c: natural := layout_c.row_low + 2;
  -- The length the board's walk uses
  constant burst_length_c: natural := 8;
  constant burst_byte_c: natural := burst_length_c * beat_byte_c;
  constant burst_count_c: natural := 2 ** region_byte_l2_c / burst_byte_c;

  constant pass_count_c: natural := 2;

  -- Bottom of the part, then its last region.
  function pass_base(pass: natural) return natural
  is
  begin
    if pass = 0 then
      return 0;
    end if;

    return 2 ** layout_c.byte_address_width - 2 ** region_byte_l2_c;
  end function;

  type error_count_vector is array (natural range <>) of unsigned(31 downto 0);
  type error_address_vector is array (natural range <>)
    of unsigned(axi_config_c.address_width - 1 downto 0);

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal axi_s: bus_t;
  signal ready_s: std_ulogic;

  signal pass_s: natural range 0 to pass_count_c - 1 := 0;
  signal start_s: std_ulogic_vector(0 to pass_count_c - 1) := (others => '0');
  signal measuring_s: std_ulogic;
  signal master_s: master_vector(0 to pass_count_c - 1);
  signal pass_done_s: std_ulogic_vector(0 to pass_count_c - 1);
  signal error_count_s: error_count_vector(0 to pass_count_c - 1);
  signal first_error_s: error_address_vector(0 to pass_count_c - 1);

  signal ck_s: nsl_io.diff.diff_pair;
  signal cke_s, cs_n_s, ras_n_s, cas_n_s, we_n_s: std_ulogic;
  signal odt_s, ram_reset_n_s: std_ulogic;
  signal ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal a_s: unsigned(address_width(part_c) - 1 downto 0);
  signal dm_s: std_ulogic_vector(lane_count_c - 1 downto 0);

  signal dqs_phy_s, dqs_model_s: nsl_io.io.tristated_vector(lane_count_c - 1 downto 0);
  signal dqs_wire_s: std_logic_vector(lane_count_c - 1 downto 0);
  signal dqs_value_s: std_ulogic_vector(lane_count_c - 1 downto 0);

  signal dq_phy_s, dq_model_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal dq_wire_s: std_logic_vector(part_c.dq_width - 1 downto 0);
  signal dq_value_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  signal activate_count_s, precharge_count_s, refresh_count_s: natural := 0;

  -- Datasheet constraints the model saw broken.  They are
  -- reported as they happen; the run has to fail on them too.
  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after controller_period_c / 2 when not stopped_s
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

  axi_s.m <= master_s(pass_s);
  measuring_s <= start_s(pass_s);

  walk: for pass in 0 to pass_count_c - 1
  generate
    tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
      generic map(
        config_c => axi_config_c,
        base_address_c => pass_base(pass),
        region_byte_l2_c => region_byte_l2_c,
        burst_length_c => burst_length_c,
        seed_c => 4242 + pass,
        scramble_c => false
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        start_i => start_s(pass),
        axi_o => master_s(pass),
        axi_i => axi_s.s,
        busy_o => open,
        done_o => pass_done_s(pass),
        error_count_o => error_count_s(pass),
        first_error_address_o => first_error_s(pass)
        );
  end generate;

  dut: nsl_ext_ram.ddr3.axi4_mm_ddr3
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      axi_config_c => axi_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      ready_o => ready_s,

      ram_ck_o => ck_s,
      ram_cke_o => cke_s,
      ram_cs_n_o => cs_n_s,
      ram_ras_n_o => ras_n_s,
      ram_cas_n_o => cas_n_s,
      ram_we_n_o => we_n_s,
      ram_ba_o => ba_s,
      ram_a_o => a_s,
      ram_odt_o => odt_s,
      ram_reset_n_o => ram_reset_n_s,
      ram_dm_o => dm_s,
      ram_dqs_o => dqs_phy_s,
      ram_dqs_i => dqs_value_s,
      ram_dq_o => dq_phy_s,
      ram_dq_i => dq_value_s
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

  -- Counts the commands the controller puts on the part's pins, so the
  -- bench can tell how many rows the walk opened and how many refreshes
  -- fell inside it.
  command_monitor: process(ck_s.p) is
    variable cmd: command_enum_t;
  begin
    if rising_edge(ck_s.p) then
      cmd := to_command_enum(dfi_config_c,
                             (cke => cke_s,
                              cs_n => cs_n_s,
                              ras_n => ras_n_s,
                              cas_n => cas_n_s,
                              we_n => we_n_s,
                              bank => resize(ba_s, nsl_ext_ram.dfi.max_bank_width_c),
                              address => resize(a_s, nsl_ext_ram.dfi.max_address_width_c),
                              odt => odt_s));

      if cke_s = '1' then
        case cmd is
          when CMD_ACTIVATE =>
            activate_count_s <= activate_count_s + 1;
          when CMD_PRECHARGE =>
            precharge_count_s <= precharge_count_s + 1;
          when CMD_REFRESH =>
            refresh_count_s <= refresh_count_s + 1;
          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  -- Times the pass under way over the AXI port and reports what a burst
  -- cost, write side and read side apart.
  traffic_monitor: process(clock_s) is
    variable cycle: natural;
    variable write_start, write_end: natural;
    variable read_start, read_end: natural;
    variable aw_count, b_count: natural;
    variable ar_count, r_count: natural;
    variable activate_at_start, precharge_at_start, refresh_at_start: natural;
    variable activate_at_read, precharge_at_read, refresh_at_read: natural;
    variable aw_stalled, w_stalled, idle: natural;
    variable ar_stalled, r_missing: natural;
    variable span: natural;
  begin
    if rising_edge(clock_s) then
      if measuring_s = '0' then
        cycle := 0;
        write_start := 0;
        write_end := 0;
        read_start := 0;
        read_end := 0;
        aw_count := 0;
        b_count := 0;
        ar_count := 0;
        r_count := 0;
        activate_at_start := 0;
        precharge_at_start := 0;
        refresh_at_start := 0;
        aw_stalled := 0;
        w_stalled := 0;
        idle := 0;
        activate_at_read := 0;
        precharge_at_read := 0;
        refresh_at_read := 0;
        ar_stalled := 0;
        r_missing := 0;
      else
        cycle := cycle + 1;

        if ar_count = 0 and aw_count /= 0 then
          if is_valid(axi_config_c, axi_s.m.aw) then
            if not is_ready(axi_config_c, axi_s.s.aw) then
              aw_stalled := aw_stalled + 1;
            end if;
          elsif is_valid(axi_config_c, axi_s.m.w) then
            if not is_ready(axi_config_c, axi_s.s.w) then
              w_stalled := w_stalled + 1;
            end if;
          else
            idle := idle + 1;
          end if;
        end if;

        -- Read side: an address the controller will not take, and a
        -- cycle the tester would have taken a beat on and got none.
        if ar_count /= 0 then
          if is_valid(axi_config_c, axi_s.m.ar)
            and not is_ready(axi_config_c, axi_s.s.ar) then
            ar_stalled := ar_stalled + 1;
          end if;
          if is_ready(axi_config_c, axi_s.m.r)
            and not is_valid(axi_config_c, axi_s.s.r) then
            r_missing := r_missing + 1;
          end if;
        end if;

        if is_valid(axi_config_c, axi_s.m.aw)
          and is_ready(axi_config_c, axi_s.s.aw) then
          if aw_count = 0 then
            write_start := cycle;
            activate_at_start := activate_count_s;
            precharge_at_start := precharge_count_s;
            refresh_at_start := refresh_count_s;
          end if;
          aw_count := aw_count + 1;
        end if;

        if is_valid(axi_config_c, axi_s.s.b)
          and is_ready(axi_config_c, axi_s.m.b) then
          write_end := cycle;
          b_count := b_count + 1;
        end if;

        if is_valid(axi_config_c, axi_s.m.ar)
          and is_ready(axi_config_c, axi_s.s.ar) then
          if ar_count = 0 then
            span := write_end - write_start + 1;
            read_start := cycle;

            report "pass " & integer'image(pass_s) & " from address "
              & integer'image(pass_base(pass_s)) & ": wrote "
              & integer'image(b_count) & " bursts of "
              & integer'image(burst_byte_c) & " bytes in "
              & integer'image(span) & " controller cycles, "
              & integer'image(span * 100 / b_count)
              & " hundredths of a cycle per burst";
            report "pass " & integer'image(pass_s) & " write spent "
              & integer'image(aw_stalled)
              & " cycles with an address the controller would not take, "
              & integer'image(w_stalled)
              & " cycles with data it would not take, and "
              & integer'image(idle)
              & " cycles with nothing offered";
            report "pass " & integer'image(pass_s) & " write took "
              & integer'image(activate_count_s - activate_at_start)
              & " activates, "
              & integer'image(precharge_count_s - precharge_at_start)
              & " precharges and "
              & integer'image(refresh_count_s - refresh_at_start)
              & " refreshes";

            activate_at_read := activate_count_s;
            precharge_at_read := precharge_count_s;
            refresh_at_read := refresh_count_s;

            assert refresh_count_s - refresh_at_start >= 2
              report "write pass is too short for two refreshes to fall in it"
              severity failure;
            assert activate_count_s - activate_at_start >= 4
              report "write pass does not open four rows"
              severity failure;
          end if;
          ar_count := ar_count + 1;
        end if;

        if is_valid(axi_config_c, axi_s.s.r)
          and is_ready(axi_config_c, axi_s.m.r) then
          read_end := cycle;
          r_count := r_count + 1;

          if r_count = burst_count_c * burst_length_c then
            span := read_end - read_start + 1;

            report "pass " & integer'image(pass_s) & ": read "
              & integer'image(ar_count) & " bursts of "
              & integer'image(burst_byte_c) & " bytes in "
              & integer'image(span) & " controller cycles, "
              & integer'image(span * 100 / ar_count)
              & " hundredths of a cycle per burst";
            report "pass " & integer'image(pass_s) & " read spent "
              & integer'image(ar_stalled)
              & " cycles with an address the controller would not take and "
              & integer'image(r_missing)
              & " cycles waiting for a beat";
            report "pass " & integer'image(pass_s) & " read took "
              & integer'image(activate_count_s - activate_at_read)
              & " activates, "
              & integer'image(precharge_count_s - precharge_at_read)
              & " precharges and "
              & integer'image(refresh_count_s - refresh_at_read)
              & " refreshes";
          end if;
        end if;
      end if;
    end if;
  end process;

  watchdog: process is
  begin
    wait for 20 ms;
    assert stopped_s
      report "watchdog fired, controller or tester is stuck"
      severity failure;
    wait;
  end process;

  stim: process is
  begin
    assert region_byte_l2_c >= layout_c.row_low + 2
      report "walk does not cross two row boundaries"
      severity failure;

    assert layout_c.bank_low < layout_c.row_low
      report "walk does not cross a bank boundary before a row boundary"
      severity failure;

    report "address map: column at bit " & integer'image(layout_c.column_low)
      & " over " & integer'image(layout_c.column_width) & " bits, bank at bit "
      & integer'image(layout_c.bank_low) & " over "
      & integer'image(layout_c.bank_width) & " bits, row at bit "
      & integer'image(layout_c.row_low) & " over "
      & integer'image(layout_c.row_width) & " bits";
    report "walking " & integer'image(2 ** region_byte_l2_c) & " bytes in "
      & integer'image(burst_count_c) & " bursts of "
      & integer'image(burst_byte_c) & " bytes";

    wait until ready_s = '1';
    report "controller ready at " & time'image(now);

    for pass in 0 to pass_count_c - 1
    loop
      wait until falling_edge(clock_s);
      pass_s <= pass;
      start_s(pass) <= '1';

      wait until pass_done_s(pass) = '1';

      assert error_count_s(pass) = 0
        report "pass " & integer'image(pass) & " found "
        & integer'image(to_integer(error_count_s(pass)))
        & " errors, first at address "
        & integer'image(to_integer(first_error_s(pass)))
        severity failure;

      report "pass " & integer'image(pass) & " done at " & time'image(now)
        & ", " & integer'image(to_integer(error_count_s(pass))) & " errors";

      wait until falling_edge(clock_s);
      start_s(pass) <= '0';
    end loop;

    assert violation_count_s = 0
      report integer'image(violation_count_s)
      & " datasheet constraints were broken on the part's pins"
      severity failure;

    stopped_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
