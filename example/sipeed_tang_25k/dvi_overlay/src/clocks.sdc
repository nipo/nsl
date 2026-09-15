create_clock -name clk_50 -period 20 -waveform {0 10} [get_nets {clock_buf/clock_s}]
create_clock -name dvi_ck -period 39.722 [get_ports {dvi_ck_i}]
