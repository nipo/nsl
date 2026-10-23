# What the board gives.  Other internal clocks come out of a PLL fed
# by it, and the timing engine follows them through.
create_clock -name clk_50_buf -period 20 -waveform {0 10} [get_nets {clock_ext_s}]

# Sensor pixel clock.  This is above what the sensor is set up to.
create_clock -name clk_pclk -period 20 -waveform {0 10} [get_nets {clock_pclk_s}]
# Nothing crosses from or to it but the framebuffer, which tears anyway.
set_false_path -from [get_clocks {clk_pclk}]
set_false_path -to [get_clocks {clk_pclk}]
