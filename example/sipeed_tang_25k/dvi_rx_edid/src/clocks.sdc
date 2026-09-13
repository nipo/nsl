create_clock -name clk_50 -period 20 -waveform {0 10} [get_nets {clock_buf/clock_s}]

# The link brings its own clock, and everything below the receiver runs
# on what the PLL makes of it.  Stating it here is what lets the timing
# report say whether the mode on offer is one this design can keep up
# with.  1280x720 at 60 asks 74.25 MHz.
create_clock -name dvi_ck -period 13.468 [get_ports {dvi_ck_i}]
