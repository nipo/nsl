create_clock -name clk_50 -period 20 -waveform {0 10} [get_nets {clock_buffer/board_clock_s}]
create_clock -name clk_100 -period 10 -waveform {0 5} [get_nets {pll_clock_s[0]}]
