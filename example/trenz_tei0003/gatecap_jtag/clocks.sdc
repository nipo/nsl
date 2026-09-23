# The board oscillator.  Nothing in this design derives a clock from
# it.
create_clock -name clk12m -period 83.333 [get_ports clk12m_i]

# TCK.  The SLD hub Quartus inserts constrains altera_reserved_tck
# itself, at 10 MHz, before this file is read, and a second
# create_clock on the port is ignored.  acrobe drives this part at
# 12 MHz, which the TCK domain's slack covers.  The transport crosses
# TCK to the oscillator in its own FIFOs.
set_clock_groups -asynchronous -group {clk12m} -group {altera_reserved_tck}

derive_clock_uncertainty

# The LEDs and the button answer to nobody's clock.
set_false_path -from [get_ports user_btn_i]
set_false_path -to [get_ports led_o[*]]
