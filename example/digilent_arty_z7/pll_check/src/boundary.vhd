library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, gatecap_generated;
use nsl_clocking.pll.all;

entity boundary is
  port(
    clock_125_i: in std_ulogic;

    ld_o: out std_ulogic_vector(0 to 3)
    );
end entity;

architecture beh of boundary is

  constant board_hz_c : natural := 125000000;
  constant phased_hz_c : natural := 12000000;
  constant rack_hz_c : natural := 100000000;
  constant sample_hz_c : natural := 87500000;

  -- Four outputs a quarter cycle apart, plus the clock the rack runs
  -- on.  The phases move the mapping: undelayed, 12MHz off this
  -- crystal comes from a 1200MHz VCO over 100, and three quarters of
  -- that cycle is 600 eighths of a VCO cycle, more shift than the
  -- block holds.  The solver settles on 900MHz over 75, which needs
  -- 450.  Both mappings divide the reference by five, which is what
  -- puts 12MHz in reach at all.
  constant phase_config_c : pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(phased_hz_c),
    o1 => pll_output(phased_hz_c, phase => (num => 1, den => 4)),
    o2 => pll_output(phased_hz_c, phase => (num => 1, den => 2)),
    o3 => pll_output(phased_hz_c, phase => (num => 3, den => 4)),
    o4 => pll_output(rack_hz_c),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("MMCM"));

  -- The sampling clock and four more rates to measure, on the other
  -- block.  Every one of them divides 1050MHz and nothing else in the
  -- PLL's window does, so this mapping is the only one.
  constant sample_config_c : pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(sample_hz_c),
    o1 => pll_output(150000000),
    o2 => pll_output(50000000),
    o3 => pll_output(25000000),
    o4 => pll_output(10000000),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("PLL"));

  signal board_s : std_ulogic;
  signal startup_reset_n_s, locked_s : std_ulogic;
  signal phase_locked_s, sample_locked_s : std_ulogic;
  signal heartbeat_reset_n_s, sample_reset_n_s : std_ulogic;

  signal phase_raw_s, phase_s
    : std_ulogic_vector(0 to phase_config_c.output_count-1);
  signal sample_raw_s, sample_s
    : std_ulogic_vector(0 to sample_config_c.output_count-1);

  signal heartbeat_s : unsigned(23 downto 0);

begin

  board_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clock_125_i,
      clock_o => board_s
      );

  startup_reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => board_s,
      reset_n_o => startup_reset_n_s
      );

  phase_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => phase_config_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,
      clock_o => phase_raw_s,
      locked_o => phase_locked_s
      );

  sample_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => sample_config_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,
      clock_o => sample_raw_s,
      locked_o => sample_locked_s
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

  sample_buffers: for i in sample_raw_s'range generate
    buffer_inst: nsl_clocking.distribution.clock_buffer
      port map(
        clock_i => sample_raw_s(i),
        clock_o => sample_s(i)
        );
  end generate;

  locked_s <= phase_locked_s and sample_locked_s;

  heartbeat_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => phase_s(0),
      data_i => locked_s,
      data_o => heartbeat_reset_n_s
      );

  sample_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => sample_s(0),
      data_i => locked_s,
      data_o => sample_reset_n_s
      );

  -- Gatecap rack over the chip TAP, riding the board crystal rather
  -- than anything the clock managers make: an instrument that only
  -- answers when its subject works tells you nothing when the subject
  -- does not.  A clock that never starts reads zero here, which is
  -- the measurement.
  observer: gatecap_generated.pll_check.pll_check_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,

      rates_board_i => board_s,
      rates_p0_i => phase_s(0),
      rates_p90_i => phase_s(1),
      rates_p180_i => phase_s(2),
      rates_p270_i => phase_s(3),
      rates_mmcm_100m_i => phase_s(4),
      rates_sample_i => sample_s(0),
      rates_f150m_i => sample_s(1),
      rates_f50m_i => sample_s(2),
      rates_f25m_i => sample_s(3),
      rates_f10m_i => sample_s(4),

      phases_sample_clock_i => sample_s(0),
      phases_sample_reset_n_i => sample_reset_n_s,
      phases_sample_p0_i => phase_s(0),
      phases_sample_p90_i => phase_s(1),
      phases_sample_p180_i => phase_s(2),
      phases_sample_p270_i => phase_s(3)
      );

  -- Enough to tell a locked board from a dead one without a host.
  heartbeat: process(phase_s(0), heartbeat_reset_n_s)
  begin
    if heartbeat_reset_n_s = '0' then
      heartbeat_s <= (others => '0');
    elsif rising_edge(phase_s(0)) then
      heartbeat_s <= heartbeat_s + 1;
    end if;
  end process;

  ld_o(0) <= phase_locked_s;
  ld_o(1) <= sample_locked_s;
  ld_o(2) <= heartbeat_s(heartbeat_s'left);
  ld_o(3) <= '0';

end architecture;
