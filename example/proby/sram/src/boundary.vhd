library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_io, nsl_amba, nsl_ext_ram,
  gatecap_generated;
use nsl_clocking.pll.all;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.sram.all;

entity boundary is
  port(
    clk: in std_ulogic;

    user_btn: in std_ulogic;
    user_led: out std_ulogic;
    jtag_en: out std_ulogic;

    ram_clk: out std_ulogic;
    ram_addr: out std_ulogic_vector(21 downto 0);
    ram_cen: out std_ulogic;
    ram_cenn: out std_ulogic;
    ram_wen: out std_ulogic;
    ram_bwan: out std_ulogic;
    ram_bwbn: out std_ulogic;
    ram_oen: out std_ulogic;

    ram_da: inout std_logic_vector(7 downto 0);
    ram_dap: inout std_logic;
    ram_db: inout std_logic_vector(7 downto 0);
    ram_dbp: inout std_logic
    );
end entity;

architecture beh of boundary is

  constant board_hz_c: natural := 12000000;
  constant rack_hz_c: natural := 36000000;
  constant ram_hz_c: natural := 126000000;
  constant tck_ps_c: natural := 1000000000 / (ram_hz_c / 1000);

  -- A Spartan-6 PLL compares at 19MHz and up, which the board
  -- oscillator is below, so the DCM's synthesizer carries the
  -- reference up first.
  constant ref_config_c: pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(rack_hz_c),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("DCM"));

  constant ram_config_c: pll_config_t := pll_config(
    input_hz => rack_hz_c,
    o0 => pll_output(ram_hz_c),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("PLL"));

  constant part_c: sram_part_t := cy7c1462av25_c;
  constant burst_cycle_c: natural := 4;

  -- Controller cycles a read takes on top of the part's own latency.
  -- One is the register that captures the bus; a board whose round
  -- trip no longer fits inside a cycle wants more.
  constant capture_ck_c: natural := 2;
  constant axi_config_c: config_t := axi_config(part_c);

  -- The whole part, walked once through in each order.
  constant region_byte_l2_c: natural := 22;

  constant lane_c: natural := part_c.dq_byte_count;

  signal board_s, rack_raw_s, rack_s, ram_raw_s, ram_s: std_ulogic;
  signal startup_reset_n_s: std_ulogic;
  signal ref_locked_s, ram_locked_s, locked_s: std_ulogic;
  signal ram_reset_n_s, walk_reset_n_s: std_ulogic;

  signal axi_s: bus_t;
  signal ready_s, busy_s, done_s: std_ulogic;
  signal parity_error_s: std_ulogic;
  signal error_count_s: unsigned(31 downto 0);
  signal first_error_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal run_s: std_ulogic;

  signal ram_bw_n_s: std_ulogic_vector(0 to lane_c - 1);
  signal ram_a_s: unsigned(part_c.address_width - 1 downto 0);
  signal dq_out_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0);
  signal dq_in_s: std_ulogic_vector(lane_c * 8 - 1 downto 0);
  signal dqp_out_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);
  signal dqp_in_s: std_ulogic_vector(lane_c - 1 downto 0);

  signal dq_pad_s: std_logic_vector(lane_c * 8 - 1 downto 0);
  signal dqp_pad_s: std_logic_vector(lane_c - 1 downto 0);

  signal heartbeat_s: unsigned(24 downto 0);

begin

  -- The FTDI reaches the chip on its dedicated programming pins, so
  -- the routing switch stays off.
  jtag_en <= '0';

  board_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk,
      clock_o => board_s
      );

  startup_reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => board_s,
      reset_n_o => startup_reset_n_s
      );

  ref_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ref_config_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,
      clock_o(0) => rack_raw_s,
      locked_o => ref_locked_s
      );

  rack_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => rack_raw_s,
      clock_o => rack_s
      );

  ram_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ram_config_c
      )
    port map(
      clock_i => rack_s,
      reset_n_i => ref_locked_s,
      clock_o(0) => ram_raw_s,
      locked_o => ram_locked_s
      );

  ram_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => ram_raw_s,
      clock_o => ram_s
      );

  locked_s <= ref_locked_s and ram_locked_s;

  memory_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => ram_s,
      data_i => locked_s,
      data_o => ram_reset_n_s
      );

  -- The tester stops for good once it is done, so a new walk needs it
  -- taken back to reset.  That is what the panel's control does.
  walk_reset_n_s <= ram_reset_n_s and run_s;

  tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_cycle_c,
      seed_c => 20260914,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => walk_reset_n_s,
      start_i => '1',
      axi_o => axi_s.m,
      axi_i => axi_s.s,
      busy_o => busy_s,
      done_o => done_s,
      error_count_o => error_count_s,
      first_error_address_o => first_error_s
      );

  controller: nsl_ext_ram.sram.axi4_mm_sram
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      axi_config_c => axi_config_c,
      burst_cycle_count_c => burst_cycle_c,
      capture_ck_c => capture_ck_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ram_reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      ready_o => ready_s,
      parity_error_o => parity_error_s,

      ram_clock_o => ram_clk,
      ram_cs_n_o => ram_cen,
      ram_cen_n_o => ram_cenn,
      ram_we_n_o => ram_wen,
      ram_bw_n_o => ram_bw_n_s,
      ram_oe_n_o => ram_oen,
      ram_a_o => ram_a_s,
      ram_dq_o => dq_out_s,
      ram_dq_i => dq_in_s,
      ram_dqp_o => dqp_out_s,
      ram_dqp_i => dqp_in_s
      );

  -- Byte lane 0 is the part's a lane, lane 1 its b lane.
  ram_bwan <= ram_bw_n_s(0);
  ram_bwbn <= ram_bw_n_s(1);

  -- The part is smaller than the pinout: the topmost address line
  -- lands on a pin the die does not carry at this density.
  ram_addr(part_c.address_width - 1 downto 0)
    <= std_ulogic_vector(ram_a_s);
  ram_addr(21 downto part_c.address_width) <= (others => '0');

  dq_pads: nsl_io.io.tristated_vector_io_driver
    generic map(
      width_c => lane_c * 8
      )
    port map(
      v_i => dq_out_s,
      v_o => dq_in_s,
      io_io => dq_pad_s
      );

  dqp_pads: nsl_io.io.tristated_vector_io_driver
    generic map(
      width_c => lane_c
      )
    port map(
      v_i => dqp_out_s,
      v_o => dqp_in_s,
      io_io => dqp_pad_s
      );

  ram_da <= dq_pad_s(7 downto 0);
  dq_pad_s(7 downto 0) <= ram_da;
  ram_db <= dq_pad_s(15 downto 8);
  dq_pad_s(15 downto 8) <= ram_db;
  ram_dap <= dqp_pad_s(0);
  dqp_pad_s(0) <= ram_dap;
  ram_dbp <= dqp_pad_s(1);
  dqp_pad_s(1) <= ram_dbp;

  observer: gatecap_generated.sram_walk.sram_walk_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,

      rates_board_i => board_s,
      rates_ram_i => ram_s,

      panel_clock_i => ram_s,
      panel_reset_n_i => ram_reset_n_s,
      panel_run_o => run_s,
      panel_ready_i => ready_s,
      panel_busy_i => busy_s,
      panel_done_i => done_s,
      panel_parity_error_i => parity_error_s,
      panel_error_count_i => error_count_s,
      panel_first_error_address_i => first_error_s
      );

  -- Enough to tell a running board from a dead one without a host.
  -- The led is active low.
  heartbeat: process(ram_s, ram_reset_n_s)
  begin
    if ram_reset_n_s = '0' then
      heartbeat_s <= (others => '0');
    elsif rising_edge(ram_s) then
      heartbeat_s <= heartbeat_s + 1;
    end if;
  end process;

  user_led <= not heartbeat_s(heartbeat_s'left);

end architecture;
