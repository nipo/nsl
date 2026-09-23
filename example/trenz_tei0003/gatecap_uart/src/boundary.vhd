library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, gatecap_generated;

-- Serial gatecap bench for a CYC1000.
--
-- The board's FT2232H holds two channels: the first is the JTAG the
-- part is configured through, the second is wired into the fabric as
-- six plain pins.  Two of them are the UART this rack is reached by,
-- and nothing here touches the other four.
--
-- One clock and no PLL: the 12 MHz oscillator on CLK12M drives the
-- transport, the instruments and the counter below alike.  1 Mbaud is
-- that rate divided by twelve, which is exact at both ends -- the
-- FT2232H's own baud generator divides the same 12 MHz -- so the link
-- carries no rate error at all.
--
-- What the panel proves, in the order a host reads it:
--
--  * scratch goes out and scratch_back comes home, so a value has
--    crossed the register file in the fabric rather than turning
--    around in the host or on the wire;
--  * ticks counts the oscillator, so a readback that moves says the
--    design is clocked and the answer is live;
--  * ping goes out as an event and comes back counted, which is the
--    same round trip taken through the panel's event path rather than
--    through its registers;
--  * the rate block measures that same oscillator against itself and
--    answers 12 MHz, which is the instrument the next rung's PLL will
--    be read with.
entity boundary is
  port(
    clk12m_i: in std_ulogic;

    -- FT2232H channel B.  bdbus0 is the FTDI's TXD, hence an input
    -- here, and bdbus1 its RXD.
    uart_rx_i: in std_ulogic;
    uart_tx_o: out std_ulogic;

    led_o: out std_ulogic_vector(7 downto 0);
    user_btn_i: in std_ulogic
    );
end entity;

architecture beh of boundary is

  signal clock_s: std_ulogic;
  signal reset_n_s: std_ulogic;

  signal scratch_s: unsigned(31 downto 0);
  signal scratch_back_s: unsigned(31 downto 0);
  signal led_s: unsigned(6 downto 0);
  signal ticks_s: unsigned(31 downto 0);
  signal button_s: std_ulogic;
  signal ping_s: std_ulogic;

  -- The line comes from another chip's clock, so it is resynchronised
  -- before the receiver's state machine is allowed to decide on it.
  signal uart_rx_sync_s: std_ulogic_vector(0 downto 0);
  signal async_s: std_ulogic_vector(1 downto 0);
  signal sync_s: std_ulogic_vector(1 downto 0);

begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk12m_i,
      clock_o => clock_s
      );

  reset: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  async_s <= user_btn_i & uart_rx_i;

  resync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => async_s'length
      )
    port map(
      clock_i => clock_s,
      data_i => async_s,
      data_o => sync_s
      );

  uart_rx_sync_s <= sync_s(0 downto 0);
  button_s <= sync_s(1);

  -- Free running from reset, never cleared: what the host watches to
  -- tell a clocked design from a design that merely answers.
  counter: process(clock_s, reset_n_s)
  begin
    if rising_edge(clock_s) then
      ticks_s <= ticks_s + 1;
    end if;
    if reset_n_s = '0' then
      ticks_s <= (others => '0');
    end if;
  end process;

  scratch_back_s <= scratch_s;

  led_o(6 downto 0) <= std_ulogic_vector(led_s);
  -- About three blinks a second off the 12 MHz pin.
  led_o(7) <= ticks_s(22);

  rack: gatecap_generated.tei0003_uart.tei0003_uart_core
    generic map(
      baud_rate_c => 1000000,
      -- One APB word per transaction is all this panel is ever read in
      -- bursts of, and the frame buffer the transport holds is sized
      -- from this.
      burst_length_l2_c => 6
      )
    port map(
      reset_n_i => reset_n_s,
      uart_rx_i => uart_rx_sync_s(0),
      uart_tx_o => uart_tx_o,

      rates_ref_i => clock_s,
      rates_board_i => clock_s,

      panel_clock_i => clock_s,
      panel_reset_n_i => reset_n_s,
      panel_scratch_o => scratch_s,
      panel_led_o => led_s,
      panel_scratch_back_i => scratch_back_s,
      panel_ticks_i => ticks_s,
      panel_button_i => button_s,
      panel_ping_o => ping_s,
      panel_ping_count_i => ping_s
      );

end architecture;
