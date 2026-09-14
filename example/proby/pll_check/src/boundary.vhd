library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, gatecap_generated;
use nsl_clocking.pll.all;

entity boundary is
  port(
    clk: in std_ulogic;

    user_btn: in std_ulogic;
    user_led: out std_ulogic;
    jtag_en: out std_ulogic
    );
end entity;

architecture beh of boundary is

  constant board_hz_c : natural := 12000000;
  constant rack_hz_c : natural := 36000000;
  constant phased_hz_c : natural := 12000000;
  constant sample_hz_c : natural := 48600000;

  -- A Spartan-6 PLL compares at 19MHz and up, which the board crystal
  -- is below, so the DCM's synthesizer carries the reference up
  -- first.  It multiplies and divides in one step and has no phase
  -- detector of its own.
  constant ref_config_c : pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(rack_hz_c),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("DCM"));

  -- Four outputs a quarter cycle apart, the clock they are sampled
  -- by, and one more rate to measure.  Three quarters of a
  -- divide-by-81 output is 486 eighths of a VCO cycle, inside the
  -- 511 the shifter holds.  48.6 MHz over 12 MHz is 81 over 20, so
  -- the sampling instant walks the whole output cycle in 81 steps.
  constant phase_config_c : pll_config_t := pll_config(
    input_hz => rack_hz_c,
    o0 => pll_output(phased_hz_c),
    o1 => pll_output(phased_hz_c, phase => (num => 1, den => 4)),
    o2 => pll_output(phased_hz_c, phase => (num => 1, den => 2)),
    o3 => pll_output(phased_hz_c, phase => (num => 3, den => 4)),
    o4 => pll_output(sample_hz_c),
    o5 => pll_output(81000000),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("PLL"));

  signal board_s, rack_raw_s, rack_s : std_ulogic;
  signal startup_reset_n_s, ref_reset_n_s : std_ulogic;
  signal ref_locked_s, phase_locked_s, locked_s : std_ulogic;
  signal rack_reset_n_s, sample_reset_n_s : std_ulogic;

  signal phase_raw_s, phase_s
    : std_ulogic_vector(0 to phase_config_c.output_count-1);

  signal heartbeat_s : unsigned(23 downto 0);

begin

  -- The FTDI reaches the chip on its dedicated programming pins, so
  -- the routing switch stays off.
  jtag_en <= '0';

  board_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk,
      clock_o => board_s
      );

  startup_reset: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => board_s,
      reset_n_o => startup_reset_n_s
      );

  ref_reset_n_s <= startup_reset_n_s and not user_btn;

  ref_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ref_config_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => ref_reset_n_s,
      clock_o(0) => rack_raw_s,
      locked_o => ref_locked_s
      );

  rack_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => rack_raw_s,
      clock_o => rack_s
      );

  phase_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => phase_config_c
      )
    port map(
      clock_i => rack_s,
      reset_n_i => ref_locked_s,
      clock_o => phase_raw_s,
      locked_o => phase_locked_s
      );

  -- Every output is measured in a domain of its own, and the four
  -- shifted ones are also sampled as plain wires.  Riding the global
  -- network is what keeps their delays matched: what reaches the
  -- analyzer is then the phase the block made, not the routing.
  phase_buffers: for i in phase_raw_s'range generate
    buffer_inst: nsl_clocking.distribution.clock_buffer
      port map(
        clock_i => phase_raw_s(i),
        clock_o => phase_s(i)
        );
  end generate;

  locked_s <= ref_locked_s and phase_locked_s;

  rack_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => rack_s,
      data_i => locked_s,
      data_o => rack_reset_n_s
      );

  sample_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => phase_s(4),
      data_i => locked_s,
      data_o => sample_reset_n_s
      );

  observer: gatecap_generated.pll_check.pll_check_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      clock_i => rack_s,
      reset_n_i => rack_reset_n_s,

      rates_board_i => board_s,
      rates_p0_i => phase_s(0),
      rates_p90_i => phase_s(1),
      rates_p180_i => phase_s(2),
      rates_p270_i => phase_s(3),
      rates_rack_i => rack_s,
      rates_sample_i => phase_s(4),
      rates_f81m_i => phase_s(5),

      phases_sample_clock_i => phase_s(4),
      phases_sample_reset_n_i => sample_reset_n_s,
      phases_sample_p0_i => phase_s(0),
      phases_sample_p90_i => phase_s(1),
      phases_sample_p180_i => phase_s(2),
      phases_sample_p270_i => phase_s(3)
      );

  -- Enough to tell a locked board from a dead one without a host.
  -- The led is active low.
  heartbeat: process(phase_s(0), rack_reset_n_s)
  begin
    if rack_reset_n_s = '0' then
      heartbeat_s <= (others => '0');
    elsif rising_edge(phase_s(0)) then
      heartbeat_s <= heartbeat_s + 1;
    end if;
  end process;

  user_led <= not heartbeat_s(heartbeat_s'left);

end architecture;
