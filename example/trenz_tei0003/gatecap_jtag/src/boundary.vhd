library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, gatecap_generated;

-- JTAG gatecap bench for a CYC1000.
--
-- The rack is reached through the part's own TAP, on the USER0 chain,
-- over the same FT2232H channel the part is configured through.  The
-- TAP pins come in as the altera_reserved_* ports Quartus expects for
-- the JTAG atom, and are handed to the transport untouched.
--
-- One clock and no PLL: the 12 MHz oscillator on CLK12M drives the
-- system side of the transport, the instruments and the counter below
-- alike.  TCK only clocks the transport's TAP side.
--
-- The panel is the serial bench's, so the two transports answer the
-- same questions:
--
--  * scratch goes out and scratch_back comes home, so a value has
--    crossed the register file in the fabric;
--  * ticks counts the oscillator, so a readback that moves says the
--    design is clocked and the answer is live;
--  * ping goes out as an event and comes back counted;
--  * the rate block measures the oscillator against itself and answers
--    12 MHz.
entity boundary is
  port(
    clk12m_i: in std_ulogic;

    altera_reserved_tck: in std_ulogic;
    altera_reserved_tms: in std_ulogic;
    altera_reserved_tdi: in std_ulogic;
    altera_reserved_tdo: out std_ulogic;

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

  signal async_s: std_ulogic_vector(0 downto 0);
  signal sync_s: std_ulogic_vector(0 downto 0);

begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk12m_i,
      clock_o => clock_s
      );

  reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  async_s(0) <= user_btn_i;

  resync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => async_s'length
      )
    port map(
      clock_i => clock_s,
      data_i => async_s,
      data_o => sync_s
      );

  button_s <= sync_s(0);

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

  rack: gatecap_generated.tei0003_jtag.tei0003_jtag_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      reset_n_i => reset_n_s,
      chip_tck_i => altera_reserved_tck,
      chip_tms_i => altera_reserved_tms,
      chip_tdi_i => altera_reserved_tdi,
      chip_tdo_o => altera_reserved_tdo,

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
