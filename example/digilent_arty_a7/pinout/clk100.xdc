set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clock_100_i }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clock_100_i }];
