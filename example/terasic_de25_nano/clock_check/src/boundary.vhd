library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_io, gatecap_generated;
use nsl_clocking.pll.all;

-- Clock bench for a DE25-Nano, reached over the part's own TAP.
--
-- It answers three questions a bitstream alone cannot:
--
--  * what rates the PLL came up at.  The transport and the measurer
--    ride the 50 MHz oscillator and not the PLL, so a rack that
--    answers says nothing about the PLL and the measured rates are
--    measurements.
--
--  * what rate the SDM's internal oscillator runs at, which the data
--    sheet does not state.
--
--  * whether a DDR output really moves a pin.  The block is handed
--    the constant halves a clock forward is made of, so the pin
--    carries a square wave at the clock rate.  The pin is driven and
--    read back through its own input buffer, and the rate counted on
--    what comes back is therefore the pin's and not a net's.  A panel
--    bit holds both halves equal on demand, which stops the pin: a
--    rate that does not follow that bit is a measurer reading
--    something else.
entity boundary is
  port(
    clk50m_i: in std_ulogic;

    led_o: out std_ulogic_vector(7 downto 0);

    -- A free header pin, driven by the DDR output block and read back
    -- through the same pad.
    ddr_loop_io: inout std_logic
    );
end entity;

architecture beh of boundary is

  constant board_hz_c: natural := 50000000;

  constant pll_config_c: pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(100000000),
    o1 => pll_output(125000000));

  signal ref_s, internal_s: std_ulogic;
  signal pll_raw_s: std_ulogic_vector(0 to 1);
  signal pll0_s, pll1_s: std_ulogic;
  signal ref_reset_n_s, locked_s, pll0_reset_n_s: std_ulogic;

  signal still_s: std_ulogic;
  signal still_sync_s: std_ulogic_vector(0 downto 0);
  signal led_s: unsigned(6 downto 0);
  signal ticks_s: unsigned(31 downto 0);
  signal locked_sync_s: std_ulogic_vector(0 downto 0);
  signal ping_s: std_ulogic;

  signal forward_s: nsl_io.diff.diff_pair;
  signal ddr_d_s: std_ulogic_vector(1 downto 0);
  signal ddr_pad_s: nsl_io.io.tristated;
  signal loopback_s: std_ulogic;

begin

  ref_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk50m_i,
      clock_o => ref_s
      );

  ref_reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => ref_s,
      reset_n_o => ref_reset_n_s
      );

  internal: nsl_clocking.oscillator.clock_internal
    port map(
      clock_o => internal_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => ref_s,
      reset_n_i => ref_reset_n_s,
      clock_o => pll_raw_s,
      locked_o => locked_s
      );

  pll0_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => pll_raw_s(0),
      clock_o => pll0_s
      );

  pll1_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => pll_raw_s(1),
      clock_o => pll1_s
      );

  pll0_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => pll0_s,
      data_i => locked_s,
      data_o => pll0_reset_n_s
      );

  -- The panel holds this in the oscillator's domain and the block
  -- below takes it in the PLL's, so it crosses.  It is a setting a
  -- host changes by hand and never at speed.
  still_resync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => 1
      )
    port map(
      clock_i => pll0_s,
      data_i(0) => still_s,
      data_o => still_sync_s
      );

  forward_s.p <= pll0_s;
  forward_s.n <= not pll0_s;

  -- The halves a forwarded clock is made of.  Held equal the pin
  -- stops.
  ddr_d_s(0) <= '0';
  ddr_d_s(1) <= not still_sync_s(0);

  forward: nsl_io.ddr.ddr_output
    port map(
      clock_i => forward_s,
      d_i => ddr_d_s,
      dd_o => ddr_pad_s.v
      );

  -- Driven whenever the PLL is locked, and let go otherwise.  The
  -- enable is what makes the pad a real bidirectional one, with the
  -- input buffer the rate below is counted through.
  ddr_pad_s.en <= pll0_reset_n_s;

  ddr_pad: nsl_io.io.tristated_io_driver
    port map(
      v_i => ddr_pad_s,
      v_o => loopback_s,
      io_io => ddr_loop_io
      );

  lock_resync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => 1
      )
    port map(
      clock_i => ref_s,
      data_i(0) => locked_s,
      data_o => locked_sync_s
      );

  counter: process(ref_s, ref_reset_n_s)
  begin
    if rising_edge(ref_s) then
      ticks_s <= ticks_s + 1;
    end if;
    if ref_reset_n_s = '0' then
      ticks_s <= (others => '0');
    end if;
  end process;

  led_o(6 downto 0) <= std_ulogic_vector(led_s);
  -- About three blinks a second off the 50 MHz pin.
  led_o(7) <= ticks_s(24);

  rack: gatecap_generated.de25_nano_clock_check.de25_nano_clock_check_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      reset_n_i => ref_reset_n_s,
      chip_tck_i => '0',
      chip_tms_i => '0',
      chip_tdi_i => '0',
      chip_tdo_o => open,

      rates_ref_i => ref_s,
      rates_pll0_i => pll0_s,
      rates_pll1_i => pll1_s,
      rates_internal_i => internal_s,
      rates_loopback_i => loopback_s,

      panel_clock_i => ref_s,
      panel_reset_n_i => ref_reset_n_s,
      panel_still_o => still_s,
      panel_led_o => led_s,
      panel_locked_i => locked_sync_s(0),
      panel_ticks_i => ticks_s,
      panel_ping_o => ping_s,
      panel_ping_count_i => ping_s
      );

end architecture;
