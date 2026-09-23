# The board oscillator.  Nothing in this design derives a clock from
# it, so this is the whole clock tree.
create_clock -name clk12m -period 83.333 [get_ports clk12m_i]

derive_clock_uncertainty

# The UART line is another chip's, resynchronised behind the port, and
# the two LEDs and the button answer to nobody's clock.
set_false_path -from [get_ports uart_rx_i]
set_false_path -from [get_ports user_btn_i]
set_false_path -to [get_ports uart_tx_o]
set_false_path -to [get_ports led_o[*]]
