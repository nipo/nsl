library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_amba, nsl_data, nsl_ext_ram;
use nsl_amba.axi4_mm.all;
use nsl_data.text.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.sram.all;

-- Walks a region of a synchronous SRAM through the controller's AXI
-- port, once in address order and once jumping about.
--
-- A part with no rows and no banks does not care which order it is
-- walked in, so unlike the DRAM benches the second pass is not there
-- to defeat a row policy.  It is there because a payload that is a
-- function of its address turns a swapped or stuck address line into a
-- data mismatch, and because it asks for half a memory burst at a
-- time, which is what puts the write masking to work.
--
-- The part model checks the bus underneath in picoseconds, so a pass
-- covers the data path and the datasheet alike.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: sram_part_t := cy7c1462av25_c;
  constant tck_ps_c: natural := 20000;
  constant tck_c: time := tck_ps_c * 1 ps;
  constant burst_cycle_c: natural := 4;
  constant flight_c: time := 500 ps;

  constant axi_config_c: config_t := axi_config(part_c);
  constant lane_c: natural := part_c.dq_byte_count;

  -- Enough to span many bursts and still walk twice in a couple of
  -- milliseconds of simulated time.
  constant region_byte_l2_c: natural := 13;
  constant pass_count_c: natural := 2;

  type natural_vector is array (natural range <>) of natural;

  -- The second pass asks for half a memory burst at a time, so the
  -- adapter has to pad what the transaction does not cover with fully
  -- masked beats and the part has to leave those bytes alone.  A
  -- controller that loses the mask corrupts the other half and the
  -- walk says so.
  constant pass_burst_c: natural_vector(0 to pass_count_c - 1)
    := (burst_cycle_c, burst_cycle_c / 2);

  subtype lanes_t is std_ulogic_vector(0 to lane_c - 1);

  type error_count_vector is array (natural range <>) of unsigned(31 downto 0);
  type error_address_vector is array (natural range <>)
    of unsigned(axi_config_c.address_width - 1 downto 0);

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal axi_s: bus_t;
  signal ready_s: std_ulogic;
  signal parity_error_s: std_ulogic;
  signal parity_bad_s: natural := 0;

  signal pass_s: natural range 0 to pass_count_c - 1 := 0;
  signal start_s: std_ulogic_vector(0 to pass_count_c - 1) := (others => '0');
  signal master_s: master_vector(0 to pass_count_c - 1);
  signal pass_done_s: std_ulogic_vector(0 to pass_count_c - 1);
  signal error_count_s: error_count_vector(0 to pass_count_c - 1);
  signal first_error_s: error_address_vector(0 to pass_count_c - 1);

  signal ram_clock_s: std_ulogic;
  signal ram_cs_n_s: std_ulogic;
  signal ram_cen_n_s: std_ulogic;
  signal ram_we_n_s: std_ulogic;
  signal ram_bw_n_s: lanes_t;
  signal ram_oe_n_s: std_ulogic;
  signal ram_a_s: unsigned(part_c.address_width - 1 downto 0);
  signal ctrl_dq_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0);
  signal ctrl_dqp_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);

  signal part_clock_s: std_ulogic;
  signal part_cs_n_s: std_ulogic;
  signal part_cen_n_s: std_ulogic;
  signal part_we_n_s: std_ulogic;
  signal part_bw_n_s: lanes_t;
  signal part_oe_n_s: std_ulogic;
  signal part_a_s: unsigned(part_c.address_width - 1 downto 0);
  signal model_dq_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0);
  signal model_dqp_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);

  signal near_dq_s: std_logic_vector(lane_c * 8 - 1 downto 0);
  signal far_dq_s: std_logic_vector(lane_c * 8 - 1 downto 0);
  signal near_dqp_s: std_logic_vector(lane_c - 1 downto 0);
  signal far_dqp_s: std_logic_vector(lane_c - 1 downto 0);
  signal near_dq_value_s: std_ulogic_vector(lane_c * 8 - 1 downto 0);
  signal far_dq_value_s: std_ulogic_vector(lane_c * 8 - 1 downto 0);
  signal near_dqp_value_s: std_ulogic_vector(lane_c - 1 downto 0);
  signal far_dqp_value_s: std_ulogic_vector(lane_c - 1 downto 0);

  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after tck_c / 2 when not stopped_s else '0';
  reset_n_s <= '1' after 3 * tck_c;

  part_clock_s <= transport ram_clock_s after flight_c;
  part_cs_n_s <= transport ram_cs_n_s after flight_c;
  part_cen_n_s <= transport ram_cen_n_s after flight_c;
  part_we_n_s <= transport ram_we_n_s after flight_c;
  part_bw_n_s <= transport ram_bw_n_s after flight_c;
  part_oe_n_s <= transport ram_oe_n_s after flight_c;
  part_a_s <= transport ram_a_s after flight_c;

  dq_wiring: for i in near_dq_s'range
  generate
    near_dq_s(i) <= nsl_io.io.to_logic(ctrl_dq_s(i));
    near_dq_s(i) <= transport nsl_io.io.to_logic(model_dq_s(i)) after flight_c;
    far_dq_s(i) <= transport nsl_io.io.to_logic(ctrl_dq_s(i)) after flight_c;
    far_dq_s(i) <= nsl_io.io.to_logic(model_dq_s(i));
  end generate;

  dqp_wiring: for i in near_dqp_s'range
  generate
    near_dqp_s(i) <= nsl_io.io.to_logic(ctrl_dqp_s(i));
    near_dqp_s(i) <= transport nsl_io.io.to_logic(model_dqp_s(i)) after flight_c;
    far_dqp_s(i) <= transport nsl_io.io.to_logic(ctrl_dqp_s(i)) after flight_c;
    far_dqp_s(i) <= nsl_io.io.to_logic(model_dqp_s(i));
  end generate;

  near_dq_value_s <= std_ulogic_vector(near_dq_s);
  far_dq_value_s <= std_ulogic_vector(far_dq_s);
  near_dqp_value_s <= std_ulogic_vector(near_dqp_s);
  far_dqp_value_s <= std_ulogic_vector(far_dqp_s);

  axi_s.m <= master_s(pass_s);

  walk: for pass in 0 to pass_count_c - 1
  generate
    tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
      generic map(
        config_c => axi_config_c,
        region_byte_l2_c => region_byte_l2_c,
        burst_length_c => pass_burst_c(pass),
        seed_c => 4242 + pass,
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

  dut: nsl_ext_ram.sram.axi4_mm_sram
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      axi_config_c => axi_config_c,
      burst_cycle_count_c => burst_cycle_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      ready_o => ready_s,
      parity_error_o => parity_error_s,

      ram_clock_o => ram_clock_s,
      ram_cs_n_o => ram_cs_n_s,
      ram_cen_n_o => ram_cen_n_s,
      ram_we_n_o => ram_we_n_s,
      ram_bw_n_o => ram_bw_n_s,
      ram_oe_n_o => ram_oe_n_s,
      ram_a_o => ram_a_s,
      ram_dq_o => ctrl_dq_s,
      ram_dq_i => near_dq_value_s,
      ram_dqp_o => ctrl_dqp_s,
      ram_dqp_i => near_dqp_value_s
      );

  model: nsl_ext_ram.simulation.sram_model
    generic map(
      part_c => part_c
      )
    port map(
      clock_i => part_clock_s,
      cs_n_i => part_cs_n_s,
      cen_n_i => part_cen_n_s,
      we_n_i => part_we_n_s,
      bw_n_i => part_bw_n_s,
      oe_n_i => part_oe_n_s,
      a_i => part_a_s,
      dq_i => far_dq_value_s,
      dq_o => model_dq_s,
      dqp_i => far_dqp_value_s,
      dqp_o => model_dqp_s,
      violation_count_o => violation_count_s
      );

  -- The ninth bit of each lane has to answer for the eight beside it.
  parity_watch: process is
    variable bad: natural := 0;
  begin
    loop
      wait until rising_edge(clock_s);
      exit when stopped_s;

      if parity_error_s = '1' then
        bad := bad + 1;
        parity_bad_s <= bad;
      end if;
    end loop;

    wait;
  end process;

  watchdog: process is
  begin
    wait for 20 ms;
    assert stopped_s
      report "watchdog fired, the controller or the tester is stuck"
      severity failure;
    wait;
  end process;

  stim: process is
    variable errors: natural := 0;
  begin
    wait until ready_s = '1';
    report "controller ready at " & time'image(now);

    for pass in 0 to pass_count_c - 1
    loop
      wait until falling_edge(clock_s);
      pass_s <= pass;
      start_s(pass) <= '1';

      wait until pass_done_s(pass) = '1';

      errors := errors + to_integer(error_count_s(pass));

      report "pass " & to_string(pass) & " done at " & time'image(now)
        & ", " & to_string(to_integer(error_count_s(pass))) & " errors"
        & ", first at address "
        & to_string(to_integer(first_error_s(pass)));

      wait until falling_edge(clock_s);
      start_s(pass) <= '0';
    end loop;

    report "axi bench done at " & time'image(now) & ", "
      & to_string(errors) & " mismatches, "
      & to_string(violation_count_s) & " datasheet violations, "
      & to_string(parity_bad_s) & " parity errors";

    assert violation_count_s = 0
      report integer'image(violation_count_s)
      & " datasheet constraints were broken on the part's pins"
      severity failure;

    stopped_s <= true;
    -- The count itself is in the report above; the exit status only
    -- has to be non-zero, and a count that is a multiple of 256 would
    -- not be.
    if errors + violation_count_s + parity_bad_s = 0 then
      nsl_simulation.control.terminate(0);
    else
      nsl_simulation.control.terminate(1);
    end if;
    wait;
  end process;

end architecture;
