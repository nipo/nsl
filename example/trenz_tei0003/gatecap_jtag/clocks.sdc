# The board oscillator.  Nothing in this design derives a clock from
# it.
create_clock -name clk12m -period 83.333 [get_ports clk12m_i]

# TCK, at the 12 MHz acrobe drives this part at.  The transport crosses
# it to the oscillator in its own FIFOs.
create_clock -name tck -period 83.333 [get_ports altera_reserved_tck]
set_clock_groups -asynchronous -group {clk12m} -group {tck}

derive_clock_uncertainty

# The LEDs and the button answer to nobody's clock.
set_false_path -from [get_ports user_btn_i]
set_false_path -to [get_ports led_o[*]]
