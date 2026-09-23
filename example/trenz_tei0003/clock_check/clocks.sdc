# The board oscillator, and what the PLL makes of it.
create_clock -name clk12m -period 83.333 [get_ports clk12m_i]

derive_pll_clocks
derive_clock_uncertainty

# What comes back through the header pin: a square wave at the PLL's
# rate, made of both halves of the DDR output's period.  It clocks
# nothing but the counter that measures it, and it arrives from
# outside the die, so nothing on it is in phase with anything else
# here whatever the two rates are.
create_clock -name ddr_loop -period 12.5 [get_ports ddr_loop_io]
set_clock_groups -asynchronous \
  -group [remove_from_collection [all_clocks] [get_clocks ddr_loop]] \
  -group [get_clocks ddr_loop]

# The UART line is another chip's, resynchronised behind the port, and
# the LEDs answer to nobody's clock.
set_false_path -from [get_ports uart_rx_i]
set_false_path -to [get_ports uart_tx_o]
set_false_path -to [get_ports led_o[*]]
