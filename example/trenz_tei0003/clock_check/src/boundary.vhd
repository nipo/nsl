library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_io, gatecap_generated;
use nsl_clocking.pll.all;

-- Clock bench for a CYC1000, reached over the board's own serial
-- port.
--
-- It answers two questions that a bitstream alone cannot, and that
-- the SDRAM bench on this board depends on the answers to:
--
--  * what rate the PLL came up at.  The transport rides the 12 MHz
--    oscillator and not the PLL, so a rack that answers says nothing
--    about the PLL and the measured rate is a measurement.
--
--  * whether a DDR output really moves a pin.  The block is handed
--    the constant halves a clock forward is made of, so the pin
--    carries a square wave at the clock rate -- twice what an output
--    register clocked by the same clock could reach.  The pin is
--    driven and read back through its own input buffer, and the
--    rate counted on what comes back is therefore the pin's and not
--    a net's.  A panel bit holds both halves equal on demand, which
--    stops the pin: a rate that does not follow that bit is a
--    measurer reading something else.
entity boundary is
  port(
    clk12m_i: in std_ulogic;

    -- FT2232H channel B.  bdbus0 is the FTDI's TXD, hence an input
    -- here, and bdbus1 its RXD.
    uart_rx_i: in std_ulogic;
    uart_tx_o: out std_ulogic;

    led_o: out std_ulogic_vector(7 downto 0);

    -- A free header pin, driven by the DDR output block and read back
    -- through the same pad.
    ddr_loop_io: inout std_logic
    );
end entity;

architecture beh of boundary is

  constant board_hz_c: natural := 12000000;
  constant fabric_hz_c: natural := 80000000;

  constant pll_config_c: pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(fabric_hz_c));

  signal ref_s, fabric_raw_s, fabric_s: std_ulogic;
  signal ref_reset_n_s, locked_s, fabric_reset_n_s: std_ulogic;

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

  -- The line comes from another chip's clock, so it is resynchronised
  -- before the receiver's state machine is allowed to decide on it.
  signal uart_rx_sync_s: std_ulogic_vector(0 downto 0);

begin

  ref_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk12m_i,
      clock_o => ref_s
      );

  ref_reset: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => ref_s,
      reset_n_o => ref_reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => ref_s,
      reset_n_i => ref_reset_n_s,
      clock_o(0) => fabric_raw_s,
      locked_o => locked_s
      );

  fabric_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => fabric_raw_s,
      clock_o => fabric_s
      );

  fabric_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => fabric_s,
      data_i => locked_s,
      data_o => fabric_reset_n_s
      );

  -- The panel holds this in the oscillator's domain and the block
  -- below takes it in the PLL's, so it crosses.  It is a setting a
  -- host changes by hand and never at speed: what a crossing costs
  -- here is one half bit on the pin, once.
  still_resync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => 1
      )
    port map(
      clock_i => fabric_s,
      data_i(0) => still_s,
      data_o => still_sync_s
      );

  forward_s.p <= fabric_s;
  forward_s.n <= not fabric_s;

  -- The halves a forwarded clock is made of: low while the clock is
  -- high, high while it is low.  Held equal the pin stops.
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
  ddr_pad_s.en <= fabric_reset_n_s;

  ddr_pad: nsl_io.io.tristated_io_driver
    port map(
      v_i => ddr_pad_s,
      v_o => loopback_s,
      io_io => ddr_loop_io
      );

  resync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => 1
      )
    port map(
      clock_i => ref_s,
      data_i(0) => uart_rx_i,
      data_o => uart_rx_sync_s
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
  -- About three blinks a second off the 12 MHz pin.
  led_o(7) <= ticks_s(22);

  rack: gatecap_generated.tei0003_clock_check.tei0003_clock_check_core
    generic map(
      baud_rate_c => 1000000,
      burst_length_l2_c => 6
      )
    port map(
      reset_n_i => ref_reset_n_s,
      uart_rx_i => uart_rx_sync_s(0),
      uart_tx_o => uart_tx_o,

      rates_ref_i => ref_s,
      rates_fabric_i => fabric_s,
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
