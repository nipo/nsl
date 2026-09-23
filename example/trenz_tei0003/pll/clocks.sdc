# The board oscillator.  The PLL output is derived from it, and
# Quartus works out its rate from the counters it settled on.
create_clock -name clk12m -period 83.333 [get_ports clk12m_i]

derive_pll_clocks
derive_clock_uncertainty

# The LEDs answer to nobody's clock.
set_false_path -to [get_ports led_o[*]]
