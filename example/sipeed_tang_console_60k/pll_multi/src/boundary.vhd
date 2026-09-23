library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;
use nsl_clocking.pll.all;

-- Blinks the two board LEDs from two outputs of one PLL, done at
-- 200MHz / 2**27 (about 1.5Hz), ready at 50MHz / 2**27 (about
-- 0.37Hz).

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic
  );
end boundary;

architecture arch of boundary is

  constant cfg_c : pll_config_t := pll_config(
    input_hz => 50_000_000,
    o0 => pll_output(200_000_000),
    o1 => pll_output(50_000_000));

  signal clock_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to cfg_c.output_count-1);
  signal locked_s : std_ulogic;

  signal cnt0_s : unsigned(26 downto 0) := (others => '0');
  signal cnt1_s : unsigned(26 downto 0) := (others => '0');

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      clock_o => pll_clock_s,
      reset_n_i => reset_n_s,
      locked_o => locked_s
      );

  blink0: process(pll_clock_s(0))
  begin
    if rising_edge(pll_clock_s(0)) then
      cnt0_s <= cnt0_s + 1;
    end if;
  end process;

  blink1: process(pll_clock_s(1))
  begin
    if rising_edge(pll_clock_s(1)) then
      cnt1_s <= cnt1_s + 1;
    end if;
  end process;

  done_led_o <= cnt0_s(cnt0_s'left);
  ready_led_o <= cnt1_s(cnt1_s'left);

end architecture;
