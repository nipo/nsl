library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_amba, nsl_ext_ram;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.sdram.all;

-- The same two passes as sdram_axi, at the rate a board runs at and
-- with the walker let go before the controller is ready.
--
-- A design with a host attached has no reason to wait: the walker's
-- reset is a control register and the controller's power-up sequence
-- takes a hundred microseconds, so the first address beat of a walk
-- is offered while that sequence is still running.  sdram_axi waits
-- for ready before starting, which leaves that whole window
-- unmeasured, and a walk stalling on a board with no read beat at all
-- is exactly what an unserved first transaction looks like.
--
-- The rate is the one the iCEPi-zero closes at rather than the round
-- 100 MHz, because every delay of the controller is resolved from it:
-- a scheduler that only issues at some resolved timings passes at one
-- rung of the ladder and not the next.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: dram_part_t := w9825g6kh_c;
  constant tck_ps_c: natural := 12500;
  constant tck_c: time := tck_ps_c * 1 ps;
  constant burst_length_l2_c: natural := 3;

  constant axi_config_c: config_t := axi_config(part_c, burst_length_l2_c);
  constant beat_byte_c: natural := cycle_byte_count(part_c);

  -- Spans several rows and every bank, and still walks twice in under
  -- a millisecond of simulated time.
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

  signal ram_clock_s: std_ulogic;
  signal ram_cke_s: std_ulogic;
  signal ram_cs_n_s: std_ulogic;
  signal ram_ras_n_s: std_ulogic;
  signal ram_cas_n_s: std_ulogic;
  signal ram_we_n_s: std_ulogic;
  signal ram_ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal ram_a_s: unsigned(address_width(part_c) - 1 downto 0);
  signal ram_dqm_s: std_ulogic_vector(beat_byte_c - 1 downto 0);
  signal ram_dq_ctrl_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal ram_dq_model_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal ram_dq_wire_s: std_logic_vector(part_c.dq_width - 1 downto 0);
  signal ram_dq_value_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  -- Datasheet constraints the model saw broken.  They are
  -- reported as they happen; the run has to fail on them too.
  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after tck_c / 2 when not stopped_s else '0';
  reset_n_s <= '1' after 3 * tck_c;

  dq_wiring: for i in ram_dq_wire_s'range
  generate
    ram_dq_wire_s(i) <= nsl_io.io.to_logic(ram_dq_ctrl_s(i));
    ram_dq_wire_s(i) <= nsl_io.io.to_logic(ram_dq_model_s(i));
  end generate;
  ram_dq_value_s <= std_ulogic_vector(to_x01(ram_dq_wire_s));

  axi_s.m <= master_s(pass_s);

  walk: for pass in 0 to pass_count_c - 1
  generate
    tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
      generic map(
        config_c => axi_config_c,
        region_byte_l2_c => region_byte_l2_c,
        burst_length_c => 2 ** burst_length_l2_c,
        seed_c => 12345 + pass,
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

  dut: nsl_ext_ram.sdram.axi4_mm_sdram
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      axi_config_c => axi_config_c,
      burst_length_l2_c => burst_length_l2_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      ready_o => ready_s,

      ram_clock_o => ram_clock_s,
      ram_cke_o => ram_cke_s,
      ram_cs_n_o => ram_cs_n_s,
      ram_ras_n_o => ram_ras_n_s,
      ram_cas_n_o => ram_cas_n_s,
      ram_we_n_o => ram_we_n_s,
      ram_ba_o => ram_ba_s,
      ram_a_o => ram_a_s,
      ram_dqm_o => ram_dqm_s,
      ram_dq_o => ram_dq_ctrl_s,
      ram_dq_i => ram_dq_value_s
      );

  model: nsl_ext_ram.simulation.sdram_model
    generic map(
      part_c => part_c
      )
    port map(
      clock_i => ram_clock_s,
      cke_i => ram_cke_s,
      cs_n_i => ram_cs_n_s,
      ras_n_i => ram_ras_n_s,
      cas_n_i => ram_cas_n_s,
      we_n_i => ram_we_n_s,
      ba_i => ram_ba_s,
      a_i => ram_a_s,
      dqm_i => ram_dqm_s,
      dq_i => ram_dq_value_s,
      dq_o => ram_dq_model_s,
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
    wait until reset_n_s = '1';
    report "reset released at " & time'image(now);

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
