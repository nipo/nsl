library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;
use nsl_clocking.pll.all;

-- 12 MHz oscillator to an 80 MHz fabric clock on a CYC1000.
--
-- The counter is there to give the PLL output a load the fitter
-- cannot remove, and its top bit reaches an LED so the rate is
-- visible: 80 MHz over 2**26 blinks a shade under one and a quarter
-- times a second.  The other LED carries the lock.
entity top is
  port(
    clk12m_i: in std_ulogic;

    led_o: out std_ulogic_vector(1 downto 0)
    );
end entity;

architecture beh of top is

  constant config_c : pll_config_t := pll_config(
    input_hz => 12_000_000,
    o0 => pll_output(80_000_000));

  signal clock_s: std_ulogic_vector(0 to 0);
  signal locked_s: std_ulogic;
  signal reset_n_s: std_ulogic;
  signal counter_s: unsigned(26 downto 0);

begin

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clk12m_i,
      clock_o => clock_s,
      reset_n_i => '1',
      locked_o => locked_s
      );

  reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_s(0),
      reset_n_o => reset_n_s
      );

  counter: process(clock_s(0), reset_n_s)
  begin
    if reset_n_s = '0' then
      counter_s <= (others => '0');
    elsif rising_edge(clock_s(0)) then
      counter_s <= counter_s + 1;
    end if;
  end process;

  led_o(0) <= counter_s(counter_s'left);
  led_o(1) <= locked_s;

end architecture;
