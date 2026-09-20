library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_amba, nsl_ext_ram;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.ddr3.all;

-- Walks a region of a DDR3 part through the controller's AXI port,
-- once in address order and once jumping across rows and banks.
--
-- The part model checks the command stream and the strobe placement,
-- so a pass means the whole chain holds: power-up sequence, mode
-- registers, bank and refresh scheduling, and a PHY that centres write
-- strobes in the eye and captures reads where the part put them.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: dram_part_t := h5tq4g63efr_c;
  -- DDR3-800: the slowest bin the part supports.
  constant tck_ps_c: natural := 2500;
  constant phase_c: natural := phase_count(part_c);
  constant controller_period_c: time := phase_c * tck_ps_c * 1 ps;

  constant axi_config_c: config_t := axi_config(part_c);
  constant beat_byte_c: natural := cycle_byte_count(part_c);
  constant lane_count_c: natural := part_c.dq_width / 8;

  -- Spans several rows and every bank.
  constant region_byte_l2_c: natural := 14;
  constant pass_count_c: natural := 2;

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

  walk: for pass in 0 to pass_count_c - 1
  generate
    tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
      generic map(
        config_c => axi_config_c,
        region_byte_l2_c => region_byte_l2_c,
        burst_length_c => 4,
        seed_c => 777 + pass,
        scramble_c => pass /= 0
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
