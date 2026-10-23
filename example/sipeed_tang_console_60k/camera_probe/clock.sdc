# What the board gives.  Both clocks this runs on come out of a PLL
# fed by it, and the timing engine follows them through.
create_clock -name clk_50_buf -period 20 -waveform {0 10} [get_nets {clock_ext_s}]

# The clock the bus below runs at.  Left to itself the tool puts a
# hundred megahertz on this, which is not what it is and hides what
# the rest of the design does or does not make.
create_clock -name clk_utmi -period 16.666 -waveform {0 8.333} [get_nets {utmi_s.phy2sie.system.clock}]
