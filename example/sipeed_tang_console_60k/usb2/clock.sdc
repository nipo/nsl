create_clock -name clk_50_buf -period 20 -waveform {0 10} [get_nets {clock_ext_s}]
